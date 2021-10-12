#package require Temberweb 1.0
#package require Tcl      8.5
source temberweb.tcl 

proc withparms {soc query_parms url_parms} {
   set x [dict get $query_parms x]
   set y [dict get $query_parms y]

   ::Temberweb::response $soc "<html><head>/withparms</head><body><br><br>$x-$y<br><br><a href=\"/\">Home</a><br></body></html>" 200 "html"
}

proc withurlparms {soc query_parms url_parms} {
   ::Temberweb::response $soc "<html><head>/withurlparms</head><body><br><br>$url_parms<br><br><a href=\"/\">Home</a><br></body></html>" 200 "html"
}

proc post_action {soc query_parms url_parms} {
   puts "in post_action"

   set lname [dict get $query_parms lname]
   set fname [dict get $query_parms fname]
   
   ::Temberweb::response $soc "<html><head>/post_action_page</head><body><br><br>Hello $fname $lname<br><br><a href=\"/\">Home</a><br></body></html>" 200 "html"
}

::Temberweb::addRoute {/withparms} withparms
::Temberweb::addRoute {/withurlparms} withurlparms
::Temberweb::addRoute {/post_action_page} post_action

# Start the server up and set your port, WWW html pages home and images home.
::Temberweb::run 8050 "./www" "templates" "images"
 
