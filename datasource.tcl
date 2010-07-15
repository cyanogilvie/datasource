# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

#	item_schema example:	<<<
#		variable item_schema		{
#			"Schema"		{schema}
#			"Table"			{table combobox \
#						-choices {sql_features sql_languages sql_packages} \
#						-initial_choice	sql_languages
#			}
#			"Owner"			{owner}
#			"Has Indexes"	{indexed checkbutton}
#			"Has Rules"		{ruled checkbutton}
#			"Has Triggers"	{hastriggers checkbutton}
#		}
# >>>

package require cflib

cflib::pclass create ds::datasource {
	superclass cflib::handlers

	property criteria		{}
	property criteria_values	""
	property quote			1
	property id_column		0	;# column to use as the ID column
	property criteria_map	{}
	property defaults 		{}
	property item_schema	{}

	variable {*}{
		can_do
		acriteria
		acriteria_values
		last_headers
	}

	constructor {args} { #<<<
		set can_do			[dict create]
		set last_headers	{}

		my configure {*}$args
	}

	#>>>
	destructor { #<<<
		my invoke_handlers destroyed
	}

	#>>>

	method get_item_schema {} { #<<<
		return $item_schema
	}

	#>>>
	method set_criteria_map {mapping} { #<<<
		set criteria_map $mapping
	}

	#>>>
	method get_criteria	{} { #<<<
		# this basically gives the form defination give from the intersection of
		# the Criteria value and the names of the field_defs array-var

		return $criteria
	}

	#>>>
	method set_criteria {arraylist} { #<<<
		# sets the criteria (and acriteria) from an array-style list.  the list
		# element style is: {criteria_label} {criteria_varname {form style}}

		set criteria $arraylist
	}

	#>>>
	method get_criteria_values {} { #<<<
		return $criteria_values
	}

	#>>>
	method set_criteria_values {arraylist} { #<<<
		# sets the replacement values for the criteria tokenlist from an
		# array-style list the list element style is:
		#	{criteria_varname} {variable_value}

		set criteria_values $arraylist
	}

	#>>>
	method set_field_defs {arraylist} { #<<<
		set field_defs $arraylist
	}

	#>>>
	method get_field_defs {} { #<<<
		return $field_defs
	}

	#>>>
	method set_defaults {rowarray} { #<<<
		set defaults $rowarray
	}

	#>>>
	method get_defaults {} { #<<<
		return $defaults
	}

	#>>>
	method get_list {criteria {headersvar {}}} { #<<<
	}

	#>>>
	method get_labelled_list {criteria {headersvar {}}} { #<<<
		# does the same as a get_list, but each row contains interleaved
		# header-names with each field; makes the loading of an array or a
		# treeview structure a lot easier for the client

		if {$headersvar ne {}} {
			upvar $headersvar headers
		}
		set rawlist		[get_list $criteria headers]
		set llist		""
		foreach rawrow $rawlist {
			set lrow	""
			foreach rawcol $rawrow head $headers {
				lappend lrow $head $rawcol
			}
			lappend llist $lrow
		}

		return $llist
	}

	#>>>
	method get_id_column {} { #<<<
		list $id_column [lindex $last_headers $id_column]
	}

	#>>>
	method add_item {item} { #<<<
	}

	#>>>
	method update_item {olditem newitem} { #<<<
	}

	#>>>
	method remove_item {item} { #<<<
	}

	#>>>
	method extract_id {row} { #<<<
		lindex $row $id_column
	}

	#>>>
	method get_full_row {id} { #<<<
		# purpose: to return all fields defined in the filed definitions for
		# the id specified -- to be used by a client who will be doing an
		# update later returns: array-style list of {col} {val} {col} {val} ...
		# this is to be implemented by the client
	}

	#>>>
	method can_do {action args} { #<<<
		if {[llength $args] == 0} {
			expr {[dict exists $can_do $action] && [dict get $can_do $action]}
		} elseif {[llength $args] == 1} {
			dict set can_do $action	[expr {[lindex $args 0]}]
		} else {
			error "Wrong # of args: must be action ?newvalue?"
		}
	}

	#>>>

	method lookup {key match {mode -exact}} { #<<<
		switch -- $mode {
			-exact -
			-glob -
			-regexp {}

			default {
				throw [list bad_match_mode $mode] "Invalid match mode: \"$mode\", must be one of -exact, -glob or -regexp"
			}
		}

		set rows	[my get_list {} headers]

		set idx		[lsearch $headers $key]
		if {$idx == -1} {
			error "Invalid key: \"$key\", must be one of \"[join $headers {", "}]\""
		}

		set matches	[lsearch -all -inline $mode -index $idx $rows $match]

		set build	{}
		foreach row $matches {
			set a	{}
			foreach h $headers v $row {
				lappend a	$h $v
			}
			lappend build	$a
		}

		return $build
	}

	#>>>
	method slice {column args} { #<<<
		# slice returns all instances of a column in the datasource, sorted
		# to taste

		set raw	[my get_list {} headers]

		# Check that the specified column is valid <<<
		if {$column ni $headers} {
			throw [list invalid_column $column] "Invalid slice column \"$column\", should be one of ([join $headers {, }])"
		}
		# Check that the specified column is valid >>>

		# Parse options <<<
		set sortcolumn	$column
		set sortmode	"dictionary"
		set sortdir		increasing

		set remaining	$args
		while {[llength $remaining] > 0} {
			set option		[lindex $remaining 0]
			set remaining	[lrange $remaining 1 end]

			if {[string index $option 0] ne "-"} {
				throw syntax_error "Expecting an option, got \"$option\""
			}

			switch -- $option {
				-orderby - -sort { #<<<
					set remaining	[lassign $remaining sortcolumn]

					if {$sortcolumn ni $headers} {
						throw [list invalid_sortcolumn $sortcolumn $headers] "Specified sort column ($sortcolumn) doesn't exist.  Should be one of ([join $headers {, }])"
					}

					if {[string index [lindex $remaining 0] 0] ne "-"} {
						set remaining	[lassign $remaining sortdir]

						switch -- $sortdir {
							asc - ascending - increasing {
								set sortdir		increasing
							}

							desc - descending - decreasing {
								set sortdir		decreasing
							}

							default {
								throw [list invalid_sortdir $sortdir] "Invalid sortdir specified: ($sortdir)"
							}
						}
					}
					#>>>
				}

				-sortmode { #<<<
					set remaining	[lassign $remaining sortmode]

					switch -- $sortmode {
						ascii - dictionary - integer - real {}

						default {
							throw [list invalid_sortmode $sortmode] "Invalid sortmode: \"$sortmode\""
						}
					}
					#>>>
				}

				default {
					throw [list invalid_option $option] "Invalid option \"$option\""
				}
			}
		}
		# Parse options >>>

		set sort_col_idx	[lsearch $headers $sortcolumn]
		set slice_col_idx	[lsearch $headers $column]

		set build	{}
		foreach row [lsort -$sortmode -$sortdir -index $sort_col_idx $raw] {
			lappend build	[lindex $row $slice_col_idx]
		}

		return $build
	}

	#>>>
	method build_map {from_column args} { #<<<
		set rows	[my get_list {} headers]

		switch -- [llength $args] {
			0 {
				error "Must specify a target column format"
			}

			1 {
				set format	"%s"
				set to_column_list	[list [lindex $args 0]]
			}

			default {
				set to_column_list	[lassign $args format]
			}
		}
		set from_idx	[lsearch $headers $from_column]
		if {$from_idx == -1} {
			error "From column \"$from_column\" doesn't exist"
		}
		set to_idx_list	{}
		foreach col $to_column_list {
			set to_idx	[lsearch $headers $col]
			if {$to_idx == -1} {
				error "To column \"$col\" doesn't exist"
			}
			lappend to_idx_list	$to_idx
		}

		set res	[dict create]
		foreach row $rows {
			set to_cols	{}
			foreach idx $to_idx_list {
				lappend to_cols [lindex $row $idx]
			}
			dict lappend res \
					[lindex $row $from_idx] \
					[format $format {*}$to_cols]
		}

		return $res
	}

	#>>>

	method _replace_criteria {str {criteria_arraylist {}} {recursion_level 0}} { #<<<
		# TODO: figure out a "proper" way to allow substitutions, and still
		# allow
		#			1) %var% string literals that match to pass through
		#			2) a barrier against infinite recursion

		set ret	$str
		if {$criteria_arraylist eq {}} {
			set driving_force	$criteria_values
		} else {
			set driving_force	$criteria_arraylist
		}
		set map_directives	{}
		array set valmappings $criteria_map
		foreach {idx val} $driving_force {
			if {[info exists valmappings($idx)]} {
				array set tmp $valmappings($idx)
				if {[info exists tmp($val)]} {
					lappend map_directives "%${idx}%" "$tmp($val)"
				} else {
					lappend  map_directives "%${idx}%" "$val"
				}
			} else {
				lappend map_directives "%${idx}%" "$val"
			}
		}
		set ret [string map "$map_directives" "$str"]
		# now, check for recursive re-inclusion of criteria within criteria only
		foreach {idx val} $criteria_values {
			if {[string first "%$idx%" $ret] != -1} {
				if {$recursion_level < 5} {
					set ret [my _replace_criteria $ret $driving_force 
								[incr recursion_level]]
				}
				break
			}
		}
		return $ret
	}

	#>>>
	method _resolve_row {row col_list} { #<<<
		# resolves a list of values (row) and a column name list (col_list)
		# into an array-style list inputs: row (raw data list); col_list:
		# column names for items in row returns: array-style list of the style:
		# {col_name} {col_value}

		foreach col $col_list val $row {
			lappend ret $col $val
		}

		return $ret
	}

	#>>>
	method _criteria_changed {} { #<<<
	}

	#>>>
}


