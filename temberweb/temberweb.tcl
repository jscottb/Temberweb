#
# TemberWeb (TimberWeb) - A simple web handling framework for small systems.
# Writtin in tcl
#
# By Scott Beasley 2016, 2021
#
# Based off of Dustmote by Harold Kaplan 1998 - 2002.
# See: http://wiki.tcl.tk/4333
#

package provide Temberweb 1.0

# Create the namespace
namespace eval ::Temberweb {
   # Export commands
   namespace export run addRoute contentType http_return response \
             requestError 404NotFound addCookie addHeader lurl_enc \
             lurl_dec html_esc getHost getContentLen getContentType \
             sendTemplate 

   variable root "./www"
   variable pages "templates"
   variable image_root "images"
   variable log "log"
   variable images {.jpg .gif .png .tif .svg}
   variable default "index.html"
   variable port 8080
   variable uri_handlers {}
   variable logging TRUE
   variable content_len
   variable content_type
   variable cookies {}
   variable headers {}   
   variable return_codes
   variable host
   variable url_enc_map {}
   variable url_dec_map {}
   variable referer {}

   array set return_codes {
      200 {200 Ok}
      204 {204 No Content}
      400 {400 Bad Request}
      401 {401 Unauthorized}
      403 {403 Forbidden}
      404 {404 Not Found}
      405 {405 Method Not Allowed}
      503 {503 Server error}
   }

   variable content_types
   array set content_types {
      {}   text/plain
      txt  text/plain
      htm  text/html
      html text/html
      gif  image/gif
      png  image/png
      jpg  image/jpeg
      json application/json
      xml  application/xml
      js   text/javascript
      css  text/css
   }
}

proc ::Temberweb::bgerror {trouble} {puts stdout "bgerror: $trouble"}

proc ::Temberweb::answer {soc host2 port2} {
   fileevent $soc readable [list ::Temberweb::processRequest $soc]
}

proc ::Temberweb::processRequest {soc} {
   variable root
   variable pages
   variable default
   variable images
   variable image_root
   variable uri_handlers
   variable content_types
   variable return_codes
   variable logging
   variable content_len
   variable content_type
   variable cookies
   variable headers
   variable host
   variable url_enc_map
   variable url_dec_map
   variable referer

   fconfigure $soc -blocking 0
   set reqLine [gets $soc]
 
   if {[fblocked $soc]} {
      return
   }

   if {[string trim $reqLine] eq {}} {
      close $soc
      return
   }

   fileevent $soc readable {}
   set req_data [split $reqLine "\n ?"]

   if {$logging == TRUE} {
      log $req_data 
   }

   # Remove the HTTP/1.1
   set req_data [lrange $req_data 0 end-1]
   set method [string trim [lindex $req_data 0]]
   set path [lindex $req_data 1]
   set parms [lindex $req_data 2]
   set content_len 0
   set content_type 0
   set post_parms {}
   set cookies {}
   set headers {}
   set host {}
   set referer {}

   after 5000 {set looper 0}
   set looper 1
   while {$looper == 1} {
      set reqLine [gets $soc]

      # Clean this up and make a proper parser
      if {[string first "CONTENT-LENGTH:" [string toupper [string trim $reqLine]]] != -1} {
         puts $reqLine
         set content_len [string trim [lindex [string range [string trim $reqLine] 14 end] 1]]
      }

      if {[string first "CONTENT-TYPE:" [string toupper [string trim $reqLine]]] != -1} {
         puts $reqLine
         set content_type [string trim [lindex [string range [string trim $reqLine] 13 end] 1]]
      }

      if {[string first "COOKIE:" [string toupper [string trim $reqLine]]] != -1} {
         set cookies [::Temberweb::cookiesTodict [string range $reqLine 8 end]]
      }

      if {[string first "HOST:" [string toupper [string trim $reqLine]]] == 0} {
         set host [string trim [string range $reqLine 6 end]]
      }

      if {[string first "REFERER:" [string toupper [string trim $reqLine]]] == 0} {
         set referer [string trim [string range $reqLine 8 end]]
      }

      if {[string trim $reqLine] == {}} {
         # Handle post data
         if {$method == "POST"} {
            if {$content_len == 0} {
               requestError $soc 400
               after cancel {set looper}
               return
            }

            set post_parms [string trim [read $soc $content_len]]
         }

         after cancel {set looper}
         break
      }
   }

   flush $soc

   set many [string length $path]
   set last [string index $path [expr {$many-1}]]
   if {$last eq {/}} {
      set path $path$default
   }

   set url_parms [split $path {/}]
   # See if there is a route handler for this path.
   foreach handler $uri_handlers {
      if {[lindex $handler 0] eq "/[lindex $url_parms 1]"} {
         set url_parms [lrange $url_parms 2 end]
         # Build a dict of the parms.
         if {$method == "POST"} {
            set query_parms_dic [::Temberweb::parmsTodict [::Temberweb::lurl_dec $post_parms]]
         } else { # Parms for all other methods (DELETE, PUT, etc.) 
            set query_parms_dic [::Temberweb::parmsTodict [::Temberweb::lurl_dec $parms]]
         }

         if {[lsearch [lindex $handler 2] $method] >= 0} {
            eval {[lindex $handler 1] $soc $method $query_parms_dic $url_parms}
         } else  {
            requestError $soc 405
            return
         }

         return
      }
   }

   set ext [file extension $path]
   if {[string match *$ext* $images]} {
      set wholeName $image_root/[file tail $path]
   } else {
      set wholeName $root/$pages/$path
   }

   if {[::Temberweb::sendFile $soc $wholeName]} {
      404NotFound $soc $path
   }
}

proc ::Temberweb::done {inChan outChan args} {
   close $inChan
   close $outChan
}

proc ::Temberweb::404NotFound {soc page} {
   variable return_codes

   puts $soc "HTTP/1.0 $return_codes(404)"
   puts $soc ""
   puts $soc "<html><head><title><No such URL.></title></head>"
   puts $soc "<body><center>"
   puts $soc "The URL you requested does not exist on this site."
   puts $soc "</center></body></html>"
   close $soc
   return
}

proc ::Temberweb::requestError {soc error_num} {
   variable return_codes

   puts $soc "HTTP/1.0 $return_codes($error_num)"
   puts $soc ""
   puts $soc "<html><head><title><$return_codes($error_num)></title></head>"
   puts $soc "<body>$return_codes($error_num)</body></html>"
   close $soc
   return
}

proc ::Temberweb::addRoute {uri callback {method {GET}}} {
   variable uri_handlers

   lappend uri_handlers [list $uri $callback $method]
}

proc ::Temberweb::contentType {ext} {
   variable content_types

   if {![info exists content_types($ext)]} {
      set ext {}
   }

   return $content_types($ext)
}

proc ::Temberweb::http_return {ret_code} {
   variable return_codes

   if {![info exists return_codes($ret_code)]} {
      set ret_code {200}
   }

   return $return_codes($ret_code)
}

proc ::Temberweb::response {soc data {code "200"} {type ""}} {
   variable content_types
   variable headers

   puts $soc "HTTP/1.1 $code"
   puts $soc "Connection: close"
   puts $soc "Content-Security-Policy: default-src 'self';\r"
   puts $soc "Content-Type: $content_types($type)"
   foreach header $headers {
      puts $soc $header 
      #puts $header
   }
   puts $soc "Content-Length: [string length $data]"
   puts $soc ""
   puts $soc $data
   close $soc
   return
}

proc ::Temberweb::parmsTodict {parms} {
   set parms_dict {}

   foreach var [split $parms "&\n"] {
      set pair [split $var {=}]
      dict set parms_dict [lindex $pair 0] [lindex $pair 1]
   }

   return $parms_dict
}

proc ::Temberweb::cookiesTodict {parms} {
   set parms_dict {}

   foreach var [split $parms ";\n"] {
      set pair [split $var {=}]
      dict set parms_dict [string trim [lindex $pair 0]] [string trim [lindex $pair 1]]
   }

   return $parms_dict
}

proc ::Temberweb::addCookie {cookiename cookieval {ttl {}} {attributes {}}} {
   variable headers
   variable host

   set line {}

   append line "Set-Cookie: $cookiename=$cookieval; HttpOnly;"

   if {$cookieval == {}} {
      append line " ; Max-Age=1"
   } elseif {$ttl != {}} {
      set now [clock seconds]
      set tzoffset [clock format [clock seconds] -format {%z}]
      # Revisit the timezone offset maths later. Probably WRONG...
      append line " Expires=[clock format [clock add $now [expr {$ttl - $tzoffset}] minutes] -format {%a, %d %b %Y %T GMT;}]"
   }

   if {$attributes != {}} {
      append line $attributes {;}
   }  

   lappend headers $line
   #puts $headers
}

proc ::Temberweb::addHeader {header} {
   variable headers

   lappend headers $header
}

proc ::Temberweb::sendFile {soc file {url_parms ""}} {
   variable content_types
   variable return_codes

   if {[catch {set fileChannel [open $file RDONLY]}]} {
      return 1
   } else {
      set ext [file extension $file]
      fconfigure $fileChannel -translation binary
      fconfigure $soc -translation binary -buffering full
      puts $soc "HTTP/1.1 $return_codes(200)"
      puts $soc "Content-Type: $content_types([string trim $ext {.}])"
      puts $soc "Connection: close"
      puts $soc ""
      fcopy $fileChannel $soc -command [list ::Temberweb::done $fileChannel $soc]
      return 0
   }
}

proc ::Temberweb::url_encdec_init {} {
   variable url_enc_map
   variable url_dec_map

   set url_dec_map {}
   set url_enc_map {}

   lappend url_dec_map + { }
   lappend url_enc_map { } +
   for {set ndx 0} {$ndx < 256} {incr ndx} {
      set chr [format %c $ndx]
      set code %[format %02x $ndx]

      lappend url_enc_map $chr $code
      lappend url_dec_map $code $chr
   }
}

proc ::Temberweb::lurl_enc {in_str} {
   variable url_enc_map  

   return [string map $url_enc_map $in_str]
}

proc ::Temberweb::lurl_dec {in_str} { 
   variable url_dec_map

   return [string map $url_dec_map $in_str]
}

proc ::Temberweb::html_esc {in_str} { 
   return [string map {\" &quot; < &lt; > &gt; & &amp; \\ &#92;} $in_str]
}

proc ::Temberweb::getHost {} { 
   variable host

   return $host
}

proc ::Temberweb::getContentLen {} { 
   variable content_len 

   return $content_len
}

proc ::Temberweb::getContentType {} { 
   variable content_type

   return $content_type
}

proc ::Temberweb::getReferer {} { 
   variable referer

   return $referer
}

proc ::Temberweb::log {req_data} {
   variable log
   variable fd_log

   set date [clock format \
             [clock seconds] -format "%a, %d %b %Y %H:%M:%S"]
   puts $fd_log "$date: $req_data"
   flush $fd_log
}

# First hackish attempt for templating. Needs a lot of work.
proc ::Temberweb::sendTemplate {soc template_name res_code} {
   variable pages
   variable root

   if [catch {set fd_in [open $root/$pages/$template_name "r"]}] {
      ::Temberweb::requestError $soc 503
      return 1
   }

   set page_data {}
   while {![eof $fd_in]} {
      set line_in [gets $fd_in]

      set full_match ""
      set left_match ""
      set body ""
      set right_match ""

      regexp {(<\?\=)(.*?)(\?>)} $line_in full_match left_match body right_match
      if {$left_match == {<?=} && $right_match == {?>}} {
         append page_data [eval $body] "\n"
      } else {
         append page_data $line_in "\n"
      }
   }

   ::Temberweb::response $soc $page_data $res_code "html"
   return 0
}

proc ::Temberweb::run {{port_in 8080} {root_in ""} {pages_in ""} {image_root_in ""} {dolog TRUE}} {
   variable port
   variable root
   variable pages
   variable image_root
   variable log
   variable fd_log
   variable logging

   set port $port_in
   if {$root_in != {}} {
      set root [string trimright $root_in {/}]
   }

   if {$pages_in != {}} {
      set pages [string trimright $pages {/}]
   }

   if {$image_root_in != {}} {
      set image_root [string trimright $image_root_in {/}]
   }

   if {$dolog == TRUE} {
      set logging TRUE
      set fd_log [open $root/$log/access.log "a"]
      ::Temberweb::log "Server started" 
   }

   # Build the http encode and decode maps
   ::Temberweb::url_encdec_init

   socket -server answer $port
   vwait forEver
   close $fd_log
}

