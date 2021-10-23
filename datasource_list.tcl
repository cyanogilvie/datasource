# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib

cflib::pclass create ds::dslist {
	superclass ds::datasource

	variable {*}{
		id_index
	}

	property list		{}		_call_onchange
	property headers	{}		_headers_changed
	property id_column	0		_id_column_changed

	constructor {args} { #<<<
		set id_index	{}

		my can_do lookup yes
		my can_do insert yes
		my can_do update yes
		my can_do delete yes

		my configure {*}$args
	}

	#>>>

	method _id_column_changed {} { #<<<
		set id_index	[my _build_index]
		my invoke_handlers id_column_changed $id_column
		my _call_onchange
	}

	#>>>
	method _headers_changed {} { #<<<
		my invoke_handlers headers_changed $headers
		my _call_onchange
	}

	#>>>
	method _call_onchange {} { #<<<
		set id_index	[my _build_index]
		my invoke_handlers onchange
	}

	#>>>
	method _build_index {} { #<<<
		set newindex	{}
		set i	0
		foreach row $list {
			set id	[lindex $row $id_column]
			if {[dict exists $newindex $id]} {
				throw [list DATASOURCE DUPLICATE_ID $id [list [dict get $newindex $id] $i]] \
					"Duplicate id value for dslist elements [dict get $newindex $id] and $i: \"$id\""
			}
			dict set newindex $id $i
			incr i
		}
		set newindex
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
	method _item2row item { #<<<
		lmap h $headers {
			if {[dict exists $item $h]} {
				dict get $item $h
			} else {
				return -level 0 {}
			}
		}
	}

	#>>>
	method add_item item { #<<<
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

		set id	[lindex $row $id_column]
		set i	[llength $list]
		if {[dict exists $id_index $id]} {
			throw [list DATASOURCE DUPLICATE_ID $id [list [dict get $id_index $id] $i]] \
				"Duplicate id value for dslist elements [dict get $id_index $id] and $i: \"$id\""
		}
		dict set id_index $id $i

		#puts "Adding item: ($row)"
		lappend list $row
		my invoke_handlers new_item {} [lindex $row $id_column] $row
		my invoke_handlers onchange

		set res
	}

	#>>>
	if 0 {
	method add_row {row} { #<<<
		lappend list $row
		my invoke_handlers onchange
	}

	#>>>
	}
	method update_item {olditem newitem} { #<<<
		set oldrow	[my _item2row $olditem]
		set newrow	[my _item2row $newitem]
		set oldid	[lindex $oldrow $id_column]
		set newid	[lindex $newrow $id_column]
		set found	0
		if {![dict exists $id_index $oldid]} {
			throw [list DATASOURCE NOT_FOUND $oldid] "Cannot update item: old id not found: \"$oldid\""
		}
		if {$oldid ne $newid} {
			if {[dict exists $id_index $newid]} {
				throw [list DATASOURCE DUPLICATE_ID $id [list [dict get $newindex $id]]] \
					"Duplicate id value for updated dslist element: [dict get $newindex $id]: \"$id\""
			}
		}
		lset list [dict get $id_index $oldid] $newrow
		if {$oldid ne $newid} {
			dict set id_index $newid	[dict get $id_index $oldid]
			dict unset id_index $oldid
		}
		my invoke_handlers change_item {} $oldid $oldrow $newrow
		my invoke_handlers onchange
	}

	#>>>
	method remove_item item { #<<<
		set oldrow	[my _item2row $item]
		set oldid	[lindex $oldrow $id_column]
		if {![dict exists $id_index $oldid]} return
		set i		[dict get $id_index $oldid]
		set list	[lreplace $list[unset list] $i $i]
		set id_index	[my _build_index]
		my invoke_handlers remove_item {} $oldid $oldrow
		my invoke_handlers onchange
	}

	#>>>
	method get_headers {} { #<<<
		set headers
	}

	#>>>
	method get id { #<<<
		if {![dict exists $id_index $id]} {
			throw [list DATASOURCE NOT_FOUND $id] "Cannot retrieve item: id not found: \"$id\""
		}
		set i		[dict get $id_index $id]
		set item	{}
		foreach h $headers v [lindex $list $i] {
			lappend item $h $v
		}
		#log debug "dslist::get ($id), index i: ($i), row: ([lindex $list $i]), item: ($item)"
		set item
	}

	#>>>
	method get_full_row id { #<<<
		my get $id
	}

	#>>>
	method pool_meta pool { #<<<
		return {}
	}

	#>>>
}


