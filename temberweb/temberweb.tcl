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
package require Tcl      8.5

# Create the namespace
namespace eval ::Temberweb {
   # Export commands
   namespace export run addRoute contentType http_return response requestError 404NotFound

   variable root "./www"
   variable pages "templates"
   variable image_root "images"
   variable log "log"
   variable images {.jpg .gif .png .tif .svg}
   variable default "index.html"
   variable port 8080
   variable uri_handlers {}
   variable logging TRUE

   variable return_codes
   array set return_codes {
      200 {200 Ok}
      204 {204 No Content}
      400 {400 Bad Request}
      404 {404 Not Found}
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
   set method [lindex $req_data 0]
   set path [lindex $req_data 1]
   set parms [lindex $req_data 2]
   set content_len 0
   set post_parms {}

   # Handle post data
   if {$method == "POST"} {
      while 1 {
         set reqLine [gets $soc]

         if {[string first "CONTENT-LENGTH:" [string toupper [string trim $reqLine]]] != -1} {
            set content_len [string trim [lindex [string range [string trim $reqLine] 7 end] 1]]
         }

         if {[string trim $reqLine] == {}} {
            if {$content_len == 0} {
               requestError $soc $return_codes(400)
               close $soc
               return
            }

            set post_parms [string trim [read $soc $content_len]]
            break
         }
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
         if {$method == "GET"} {
            set query_parms_dic [::Temberweb::parmsTodict $parms]
         }

         if {$method == "POST"} {
            set query_parms_dic [::Temberweb::parmsTodict $post_parms]
         }

         eval {[lindex $handler 1] $soc $query_parms_dic $url_parms}
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

   puts $soc "HTTP/1.0 $code"
   puts $soc "Content-Type: $content_types($type)"
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

proc ::Temberweb::sendFile {soc file {url_parms ""}} {
   variable content_types
   variable return_codes

   if {[catch {set fileChannel [open $file RDONLY]}]} {
      return 1
   } else {
      set ext [file extension $file]
      fconfigure $fileChannel -translation binary
      fconfigure $soc -translation binary -buffering full
      puts $soc "HTTP/1.0 $return_codes(200)"
      puts $soc "Content-Type: $content_types([string trim $ext {.}])"
      puts $soc "Connection: close"
      puts $soc ""
      fcopy $fileChannel $soc -command [list ::Temberweb::done $fileChannel $soc]
      return 0
   }
}

proc ::Temberweb::log {req_data} {
   variable log
   variable fd_log

   set date [clock format \
             [clock seconds] -format "%a, %d %b %Y %H:%M:%S"]
   puts $fd_log "$date: $req_data"
   flush $fd_log
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

   socket -server answer $port
   vwait forEver
   close $fd_log
}
