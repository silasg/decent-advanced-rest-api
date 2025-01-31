package require de1_machine
package require json

set plugin_name "advanced_rest_api"

namespace eval ::plugins::${plugin_name} {

    variable author "Yannick Dietler"
    variable contact "ydt@ydt.ch"
    variable version 1.0
    variable description "API to control the DE1's power state and getting additional Information"
    variable name "Advanced REST API"

	# based on Johanna Schander's Web API
    proc main {} {
        package require wibble

        # Create settings if non-existant
        if {[array size ::plugins::advanced_rest_api::settings] == 0} {
            array set ::plugins::advanced_rest_api::settings {
                webserver_port 8888
                webserver_authentication_key "myFancyAuthenticationKey"
            }
            save_plugin_settings advanced_rest_api
        }

    

	# Auth

	proc ::wibble::check_auth {state} {
		set auth [dict getnull $state request query auth]
		set auth [lindex $auth 1]

		if {$auth eq "" && $::plugins::advanced_rest_api::settings(webserver_authentication) == 1} {
			return [unauthorized $state]
		}

		if {$auth != $::plugins::advanced_rest_api::settings(webserver_authentication_key) && $::plugins::advanced_rest_api::settings(webserver_authentication) == 1} {
			return [unauthorized $state]
		}

		return true;
	}

	proc ::wibble::unauthorized {state} {
		dict set response status 403
		dict set state response header content-type "" {application/json charset utf-8}
		dict set response content "{status: \"unauthorized\"}"
		sendresponse $response
		return false;
	}

	# Utilities

	proc ::wibble::return_200_json {content} {
		dict set response status 200
		dict set state response header content-type "" {application/json charset utf-8}
		dict set response content "$content"
		sendresponse $response
	}
	# from https://wiki.tcl-lang.org/page/JSON
	proc ::wibble::compile_json {spec data} {
      while [llength $spec] {
          set type [lindex $spec 0]
          set spec [lrange $spec 1 end]

          switch -- $type {
              dict {
                  lappend spec * string

                  set json {}
                  foreach {key val} $data {
                      foreach {keymatch valtype} $spec {
                          if {[string match $keymatch $key]} {
                              lappend json [subst {"$key":[
                                  ::wibble::compile_json $valtype $val]}]
                              break
                          }
                      }
                  }
                  return "{[join $json ,]}"
              }
              list {
                  if {![llength $spec]} {
                      set spec string
                  } else {
                      set spec [lindex $spec 0]
                  }
                  set json {}
                  foreach {val} $data {
                      lappend json [::wibble::compile_json $spec $val]
                  }
                  return "\[[join $json ,]\]"
              }
              string {
                  if {[string is double -strict $data]} {
                      return $data
                  } else {
                      return "\"$data\""
                  }
              }
              default {error "Invalid type"}
          }
      }
  }

	# Index endpoint
	proc ::wibble::indexpage {state} {
		   if { ![check_auth $state] } {
			return;
		}
		set fp [open "[homedir]/[plugin_directory]/advanced_rest_api/index.html" r]
		set file_data [read $fp]
		close $fp

	    dict set state response status 200
		dict set state response header content-type "" text/html
		dict set state response content $file_data
		sendresponse [dict get $state response]
	}

	# Profile endpoints

	proc ::wibble::profile {state } {
		if { ![check_auth $state] } {
			return;
		}
		set method [dict get $state request method]		
		if {$method eq "POST"} {
			set postdata [dict get $state request rawpost]
			set localfilename "[clock seconds].tcl"
			set path "[pwd]/profiles/$localfilename"
			set fileId [open $path "w"]
			puts -nonewline $fileId $postdata
			close $fileId
			::wibble::return_200_json "$localfilename written"
		}
		if {$method eq "GET"} {
		set path [dict get $state request path]
		set profile [lindex [split $path "/"] 3]
		

		if {$profile != ""} {
			set fd [open "[pwd]/profiles/$profile" r]
			fconfigure $fd -translation binary
			set content [read $fd]; close $fd
			# ::wibble::return_200_json   [::wibble::compile_json {dict} $content]
			::wibble::return_200_json $content
		} else {
			::wibble::return_200_json [::wibble::compile_json {list} [glob -tails -directory [pwd]/profiles/ *.tcl]]
		}
		}
		if {$method eq "PUT"} {
			#change the profile to ?
		}
		
	}
	

	#history
	proc ::wibble::history {state} {
		if { ![check_auth $state] } {
			return;
		}
		set path [dict get $state request path]
		set shot [lindex [split $path "/"] 3]


		if {$shot != ""} {
			set fd [open "[pwd]/history/$shot" r]
			fconfigure $fd -translation binary
			set content [read $fd]; close $fd
			::wibble::return_200_json $content
		} else {
			set shotlist [glob -tails -directory [pwd]/history/ *.shot]
			::wibble::return_200_json  [::wibble::compile_json "{list}" $shotlist]
		}
	}

	# based on https://github.com/Testsubject1683/de1-mirror/tree/webapi
	proc ::wibble::status {} {
	
		# depending on the current state, we supply different type of data
		set return [dict create]
		set json_structure {dict state string}
		dict set return "state" $::de1_num_state($::de1(state))
		dict set return "substate" $::de1_substate_types($::de1(substate))
		switch -- $::de1_num_state($::de1(state)) {
			"Idle" {
				dict set return "profile" $::settings(original_profile_title)
				dict set return "espresso_count" $::settings(espresso_count)
				dict set return "steaming_count" $::settings(steaming_count)
				dict set return "bean_brand" $::settings(bean_brand)
				dict set return "bean_type" $::settings(bean_type)
				dict set return "bean_notes" $::settings(bean_notes)
				dict set return "roast_date" $::settings(roast_date)
				dict set return "roast_level" $::settings(roast_level)
				dict set return "skin" $::settings(skin)
				dict set return "head_temperature" $::de1(head_temperature)
				dict set return "mix_temperature" $::de1(mix_temperature)
				dict set return "steam_heater_temperature" $::de1(steam_heater_temperature)
			}
			"Espresso" {
				foreach key [list "espresso_elapsed" "espresso_pressure" "espresso_weight" "espresso_flow" "espresso_flow_weight" "espresso_temperature_basket" "espresso_temperature_mix"] {
					#dict append ret "$key" [::${key} range 0 end]
					append json_structure " ${key} list"
					dict set return $key [split [::${key} range 0 end] " "]
				}
			}
		    "Sleep" {
			}
		    "GoingToSleep" {
			}
		    "Busy" {
			}
		    "Steam" {
			}
		    "HotWater" {
			}
		    "ShortCal" {
			}
		    "SelfTest" {
			}
		    "LongCal" {
			}
		    "Descale" {
			}
		    "FatalError" {
			}
		    "Init" {
			}
		    "NoRequest" {
			}
		    "SkipToNext" {
			}
		    "HotWaterRinse" {
			}
		    "SteamRinse" {
			}
		    "Refill" {
			}
		    "Clean" {
			}
		    "InBootLoader" {
			}
		    "AirPurge" {
			}
		}
		append json_structure " * string"
		::wibble::return_200_json [::wibble::compile_json $json_structure $return]
	}
	proc ::wibble::docs {state} {
		set fp [open "[homedir]/[plugin_directory]/advanced_rest_api/doc.json" r]
		set file_data [read $fp]
		close $fp

	    
		 ::wibble::return_200_json $file_data
	}

	proc ::wibble::state {state} {
		if { ![check_auth $state] } {
			return;
		}
		set method [dict get $state request method]
		set current_state $::de1_num_state($::de1(state))

		if {$method eq "GET"} {
			set path [dict get $state request path]
			
			switch -- $path {
				"/api/status/details" {
					::wibble::status
				}
				"/api/status" {
					if { $::de1_num_state($::de1(state)) != "Sleep" } {
						dict set state_response is_active true
						dict set state_response espresso_count $::settings(espresso_count)
					dict set state_response steaming_count $::settings(steaming_count)
					} else {
						dict set state_response is_active false
					}
					
					::wibble::return_200_json [::wibble::compile_json {dict} $state_response]
				}
			}
		}
		if  {$method eq "POST"} {
			set postdata [::json::json2dict [dict get $state request rawpost]]
			if {[dict exists $postdata active]} {
				set new_state [dict get $postdata active]
				switch -- $new_state {
					"false" {
					if {$current_state != "Sleep"} {
		 				start_sleep
		 			}
					 dict set state_change_response is_active false
					 	::wibble::return_200_json [::wibble::compile_json {dict} $state_change_response]
					
					}
					"true" {
						if {$current_state != "Idle"} {
		 				start_idle
		 			}
					 dict set state_change_response is_active true
					 	::wibble::return_200_json [::wibble::compile_json {dict} $state_change_response]
				}
				}
				

			} else {
				::wibble::return_200_json {}
			}	
			}
	}

	proc ::wibble::flushLog {state} {
		if { ![check_auth $state] } {
			return;
		}

		::logging::flush_log

		::wibble::return_200_json 
	}


	# Define handlers

		::wibble::handle /api/status state
        ::wibble::handle /api/flush flushLog
        ::wibble::handle /api/profile profile
		::wibble::handle /api/shot history
		::wibble::handle /api/help docs
		::wibble::handle / indexpage


        # Start a server and enter the event loop if not already there.

        catch {
		::wibble::listen $::plugins::advanced_rest_api::settings(webserver_port)
        }

	}  ;# main
}
