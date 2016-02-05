#
# EmberWeb - A simple web handling framework for small systems.
# Writtin in tcl
#
# By Scott Beasley 2016
#
# Based off of Dustmote by Harold Kaplan 1998 - 2002.
# See: http://wiki.tcl.tk/4333
#

package provide emberweb 1.0
package require Tcl      8.5

# Create the namespace
namespace eval ::emberweb {
    # Export commands
   namespace export run addRoute contentType

   variable root "C:/Users/jscottb/work/dustbunny/templates"
   variable image_root "C:/Users/jscottb/work/dustbunny/images"
   variable images {.jpg .gif .png .tif .svg}
   variable default "index.html"
   variable port 8080
   variable uri_handlers {}

   variable return_codes
   array set return_codes {
      200 {200 Ok}
      204 {204 No Content}
      400 {400 Bad Request}
      404 {404 Not Found}
   }

   variable content_types
   array set content_types {
      {}    text/plain
      txt  text/plain
      htm  text/html
      html text/html
      gif  image/gif
      png  image/png
      jpg  image/jpeg
      json application/json
   }
}

proc ::emberweb::bgerror {trouble} {puts stdout "bgerror: $trouble"}

proc ::emberweb::answer {soc host2 port2} {
   fileevent $soc readable [list ::emberweb::processRequest $soc]
}

proc ::emberweb::processRequest {soc} {
   variable root
   variable default
   variable images
   variable image_root
   variable uri_handlers
   variable content_types
   variable return_codes

   fconfigure $soc -blocking 0
   set reqLine [gets $soc]
   if {[fblocked $soc]} {
      return
   }

   fileevent $soc readable {}
   set req_data [split $reqLine "\n ?"]
   # Remove the HTTP/1.1
   set req_data [lrange $req_data 0 end-1]
   set method [lindex $req_data 0]
   set path [lindex $req_data 1]
   set parms [lindex $req_data 2]
   puts "<$method> <$path> <$parms>"
   set many [string length $path]
   set last [string index $path [expr {$many-1}]]
   if {$last eq {/}} {
      set path $path$default
   }

   foreach handler $uri_handlers {
      if {[lindex $handler 0] == $path} {
         eval {[lindex $handler 1] $soc $parms}
	       return
      }
   }

   set ext [file extension $path]
   if {[string match *$ext* $images]} {
      set wholeName $image_root$path
   } else {
      set wholeName $root$path
   }

   if {[catch {set fileChannel [open $wholeName RDONLY]}]} {
      404NotFound $soc $path
   } else {
      fconfigure $fileChannel -translation binary
      fconfigure $soc -translation binary -buffering full
      puts $soc "HTTP/1.0 $return_codes(200)"
      puts $soc "Content-Type: $content_types([string trim $ext "."])"
      puts $soc "Connection: close"
      puts $soc ""
      fcopy $fileChannel $soc -command [list ::emberweb::done $fileChannel $soc]
   }
}

proc ::emberweb::done {inChan outChan args} {
   close $inChan
   close $outChan
}

proc ::emberweb::404NotFound {soc page} {
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

proc ::emberweb::addRoute {uri callback} {
   variable uri_handlers

   lappend uri_handlers [list $uri $callback]
}

proc ::emberweb::contentType {ext} {
   variable content_types

   if {![info exists content_types($ext)]} {
      set ext {}
   }

   return $content_types($ext)
}

proc ::emberweb::run {{port_in 8080} {root_in ""} {image_root_in ""}} {
   variable port
   variable root
   variable image_root

   set port $port_in
   if {$root_in != {}} {
      set root $root_in
   }

   if {$image_root_in != {}} {
      set image_root $image_root_in
   }

   socket -server answer $port
   vwait forEver
}
