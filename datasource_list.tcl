# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib

cflib::pclass create ds::dslist {
	superclass ds::datasource

	property list		{}		_call_onchange
	property headers	{}		_call_onchange
	property id_column	0		_call_onchange

	constructor {args} { #<<<
		my can_do lookup yes
		my can_do insert yes
		my can_do update yes
		my can_do delete yes

		my configure {*}$args
	}

	#>>>

	method _call_onchange {} { #<<<
		my invoke_handlers onchange
	}

	#>>>
	method get_list {a_criteria {headersvar {}}} { #<<<
		if {$headersvar ne {}} {
			upvar $headersvar h
			set h	$headers
			#puts "DSlist::get_list: setting headers: ($h)"
		}

		set last_headers $headers

		#puts "DSlist::get_list: returning list: ($list)"
		return $list
	}

	#>>>
	method add_item {item} { #<<<
		set row		{}
		set res		{}
		foreach h $headers {
			if {[dict exists $item $h]} {
				set val	[dict get $item $h]
				lappend row $val
				lappend res	$h $val
			} else {
				lappend row ""
				lappend res $h ""
			}
		}

		#puts "Adding item: ($row)"
		lappend list $row
		my invoke_handlers onchange

		return $res
	}

	#>>>
	method add_row {row} { #<<<
		lappend list $row
		my invoke_handlers onchange
	}

	#>>>
	method update_item {olditem newitem} { #<<<
	}

	#>>>
	method remove_item {item} { #<<<
	}

	#>>>
	method get_headers {} { #<<<
		set headers
	}

	#>>>
}


