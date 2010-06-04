# vim: foldmethod=marker foldmarker=<<<,>>> ft=tcl ts=4 shiftwidth=4

# Datasource_filter is a datasource stacked on top of another datasource.
#	Items can be filtered to a subset of the source datasource by means of
#	filter expressions that each row must pass to be included in our filtered
#	set.
#	Items may also be translated (and have the header list changed) by 
#	a translator that given an input row, produces the output row.

# Events fired
#	init()
#	onchange()
#	id_column_changed(new_id_column)
#	headers_changed(new_headerlist)
#	new_item(pool, id, newitem)
#	change_item(pool, id, olditem, newitem)
#	remove_item(pool, id, olditem)
#	new_pool(pool)
#	remove_pool(pool)

package require cflib
package require sop

cflib::pclass create ds::datasource_filter {
	superclass ds::datasource cflib::baselog

	property ds					""		_ds_changed
	property setup				{}		_need_refilter
	property override_headers	{}		_need_refilter
	property filter				true	_filter_changed
	property translator			{}		_need_refilter
	property id_column			""		_id_column_parameter_changed
	property debug				0

	variable {*}{
		link_id_column
		damp_onchange
		dominos
		have_ftu
		_custom_keys
	}

	constructor {args} { #<<<
		set link_id_column		1
		set damp_onchange		1
		set have_ftu			0
		set _custom_keys		[dict create]

		my log debug [self]
		set have_ftu	[expr {![catch {package require ftu}]}]

		array set dominos	{}

		sop::domino new dominos(need_refilter) -name "[self] need_refilter"

		my configure {*}$args

		foreach reqf {ds} {
			if {![info exists $reqf]} {
				throw [list missing_field $reqf] "Must set -$reqf"
			}
		}

		if {$ds eq ""} {
			throw {missing_field ds} "Must set -ds"
		}
		my log debug "Filtering ds ($ds): ($filter), override_headers: ($override_headers)"

		$dominos(need_refilter) attach_output [my code _refilter]

		$ds register_handler init				[my code _init]
		$ds register_handler onchange			[my code _onchange]
		$ds register_handler id_column_changed	[my code _id_column_changed]
		$ds register_handler headers_changed	[my code _headers_changed]
		$ds register_handler new_item			[my code _new_item]
		$ds register_handler change_item		[my code _change_item]
		$ds register_handler remove_item		[my code _remove_item]
		$ds register_handler new_pool			[my code _new_pool]
		$ds register_handler remove_pool		[my code _remove_pool]
	}

	#>>>
	destructor { #<<<
		my log debug $this

		$dominos(need_refilter) detach_output [my code _refilter]

		if {[info exists ds] && [info object isa object $ds]} {
			$ds deregister_handler init 			[my code _init]
			$ds deregister_handler onchange			[my code _onchange]
			$ds deregister_handler id_column_changed [my code _id_column_changed]
			$ds deregister_handler headers_changed	[my code _headers_changed]
			$ds deregister_handler new_item			[my code _new_item]
			$ds deregister_handler change_item		[my code _change_item]
			$ds deregister_handler remove_item		[my code _remove_item]
			$ds deregister_handler new_pool			[my code _new_pool]
			$ds deregister_handler remove_pool		[my code _remove_pool]
		}
	}

	#>>>

	method _id_column_parameter_changed {} { #<<<
		if {$id_column eq ""} {
			set link_id_column	1
			if {
				[info exists ds] &&
				[info object isa object $ds] &&
				[info object isa typeof $ds ds::datasource]
			} {
				set id_column		[$ds cget -id_column]
			}
		} else {
			set link_id_column	0
		}
	}

	#>>>
	method _ds_changed {} { #<<<
		if {
			![info object isa object $ds] ||
			!(
				[info object isa typeof $ds ds::dschan] ||
				[info object isa typeof $ds ds::datasource_filter]
			)
		} {
			if {![info object isa object $ds]} {
				my log error "-ds ($ds) is not an object"
			} elseif {
				!(
					[info object isa typeof $ds ds::dschan] ||
					[info object isa typeof $ds ds::datasource_filter]
				)
			} {
				my log error "-ds ($ds) is not a ds::dschan or ds::datasource_filter"
			} else {
				my log error "non-specific -ds ($ds) problem"
			}
			throw {invalid_ds} \
					"Only ds::dschan, ds::datasource_filter and their subclasses are allowed for -ds"
		}

		if {$link_id_column} {
			set id_column	[$ds cget -id_column]
		}
		my _need_refilter
	}

	#>>>
	method _filter_changed {} { #<<<
		if {[string trim $filter] eq ""} {
			throw [list invalid_filter $filter] "-filter cannot be blank"
		}
		my _need_refilter
	}

	#>>>

	method get_list {criteria {headersvar {}}} { #<<<
		if {$headersvar ne {}} {
			upvar $headersvar hdrs
		} else {
			set hdrs	{}
		}

		set list	[dict values [lindex [my get_list_extended $criteria hdrs] 1]]

		lsort -unique -index $id_column [concat {*}$list]
	}

	#>>>
	method get_list_extended {criteria {headersvar {}}} { #<<<
		if {$headersvar ne {}} {
			upvar $headersvar hdrs
		}

		lassign [my _get_compose_info $criteria] \
				base_data \
				filters \
				translators \
				hdrs \
				custom_keys \
				override_headers_list

		lassign $base_data pool_meta pool_data

		if {$override_headers ne {}} {
			set outhdrs		$override_headers
			set use_trans	1
			if {$setup ne {}} {apply [list {} $setup]}
		} else {
			set outhdrs		$hdrs
			set use_trans	0
			foreach translator $translators {
				if {$translator ne {}} {
					set use_trans	1
					break
				}
			}
			foreach oh $override_headers_list {
				if {$oh ne {}} {
					set use_trans	1
					break
				}
			}
		}

		set last_override_headers {}
		foreach oh $override_headers_list {
			if {$oh ne {}} {
				set last_override_headers	$oh
			}
		}
		set build		{}
		if {$have_ftu} { #<<<
			dict for {pool data} $pool_data {
				set meta	[dict get $pool_meta $pool]

				set new_pool_data	{}
				foreach r $data {
					set row	[ftu::hv2dict $hdrs $r]

					set passes	1
					foreach filter $filters translator $translators {
						try {
							expr $filter
						} on error {errmsg options} {
							log error "Problem applying filter ($filter): $errmsg"
							set passes	0
							break
						} on ok {res} {
							set passes	$res
							break
						}

						if {$use_trans} $translator
					}
					if {$passes} {
						if {$use_trans} {
							lappend new_pool_data	[ftu::dictvals2list2 $row $outhdrs]
						} else {
							lappend new_pool_data	$r
						}
					}
				}
				lappend build	$pool $new_pool_data
			}
			#>>>
		} else { #<<<
			dict for {pool data} $pool_data {
				set meta	[dict get $pool_meta $pool]

				set new_pool_data	{}
				foreach r $data {
					set row	[dict create]
					foreach h $hdrs v $vals {
						dict set row $h $v
					}

					set passes	1
					foreach filter $filters translator $translators {
						try {
							expr $filter
						} on error {errmsg options} {
							log error "Problem applying filter ($filter): $errmsg"
							set passes	0
							break
						} on ok {res} {
							set passes	$res
							if {!($passes)} break
						}

						if {$use_trans} $translator
					}

					if {$passes} {
						if {$use_trans} {
							set outrow	{}
							foreach h $outhdrs {
								lappend outrow	[dict get $row $h]
							}
							lappend new_pool_data	$outrow
						} else {
							lappend new_pool_data	$r
						}
					}
				}
				lappend build	$pool $new_pool_data
			}
			#>>>
		}

		if {$last_override_headers ne {}} {
			set hdrs	$last_override_headers
		}
		set last_headers	$hdrs

		if {$debug} {
			log debug "Returning pool_meta: ($pool_meta), data: ([llength $build] items)"
		}
		list $pool_meta $build
	}

	#>>>
	method get_headers {} { #<<<
		if {$override_headers ne {}} {
			set outhdrs		$override_headers
		} else {
			set outhdrs		[$ds get_headers]
		}
		return $outhdrs
	}

	#>>>
	method pool_meta {pool} { #<<<
		$ds pool_meta $pool
	}

	#>>>
	method set_custom_key {key val} { #<<<
		dict set _custom_keys $key $val
	}

	#>>>
	method get_custom_key_dict {} { #<<<
		return $_custom_keys
	}

	#>>>

	method _need_refilter {} { #<<<
		$dominos(need_refilter) tip
	}

	#>>>
	method _refilter {} { #<<<
		#my invoke_handlers init
		my invoke_handlers onchange
	}

	#>>>
	method _init {} { #<<<
		my invoke_handlers onchange
		my invoke_handlers init
	}

	#>>>
	method _onchange {} { #<<<
		if {!($damp_onchange)} {
			my invoke_handlers onchange
			set damp_onchange	1
		}
	}

	#>>>
	method _id_column_changed {new_id_column} { #<<<
		if {$link_id_column} {
			set id_column	$new_id_column
			set damp_onchange	0
			my invoke_handlers id_column_changed $id_column
		}
	}

	#>>>
	method _headers_changed {new_headerlist} { #<<<
		if {$override_headers eq {}} {
			set last_headers	$new_headerlist
			set damp_onchange	0
			my invoke_handlers headers_changed $new_headerlist
		}
	}

	#>>>
	method _new_item {pool id newitem} { #<<<
		set hdrs		[$ds get_headers]
		set meta		[$ds pool_meta $pool]

		set row	{}
		foreach h $hdrs v $newitem {
			lappend row $h $v
		}

		#my log debug "testing against filter: ($filter)"
		try {
			if {![expr $filter]} return
		} on error {errmsg options} {
			throw [list filter_error $errmsg] "Error applying filter ($filter): $errmsg"
		}
		#my log debug "survives filter"

		set use_trans	[expr {$translator ne {}}]

		if {$use_trans} $translator
		#my log debug "after translator:"
		#parray row

		if {$use_trans} {
			set outrow	{}
			foreach h $last_headers {
				lappend outrow	[dict get $row $h]
			}
			set id		[lindex $outrow $id_column]
		} else {
			set outrow	$newitem
		}
		#log debug "id: ($id) outrow: ($outrow)"

		set damp_onchange	0
		my invoke_handlers new_item $pool $id $outrow
	}

	#>>>
	method _change_item {pool id olditem newitem} { #<<<
		set hdrs		[$ds get_headers]
		set meta		[$ds pool_meta $pool]

		# Process olditem <<<
		set row	{}
		foreach f $olditem h $hdrs {
			lappend row $h	$f
		}

		set use_trans	[expr {$translator ne {}}]

		set old_visible		[expr $filter]

		if {$old_visible} {
			if {$use_trans} $translator

			if {$use_trans} {
				set old_outrow	{}
				foreach h $last_headers {
					lappend old_outrow	[dict get $row $h]
				}
			} else {
				set old_outrow	$olditem
			}
			set old_id		[lindex $old_outrow $id_column]
		}
		# Process olditem >>>
		# Process newitem <<<
		set row	{}
		foreach f $newitem h $hdrs {
			lappend row $h	$f
		}

		set new_visible		[expr $filter]

		if {$new_visible} {
			if {$use_trans} $translator

			if {$use_trans} {
				set new_outrow	{}
				foreach h $last_headers {
					lappend new_outrow	[dict get $row $h]
				}
			} else {
				set new_outrow	$newitem
			}
			set new_id		[lindex $new_outrow $id_column]
		}
		# Process newitem >>>

		set damp_onchange	0
		switch -- $old_visible,$new_visible {
			0,0 {set damp_onchange	1}
			1,0 {my invoke_handlers remove_item $pool $old_id $old_outrow}
			0,1 {my invoke_handlers new_item $pool $new_id $new_outrow}
			1,1 {my invoke_handlers change_item $pool $old_id $old_outrow $new_outrow}
		}
	}

	#>>>
	method _remove_item {pool id olditem} { #<<<
		set hdrs		[$ds get_headers]
		set meta		[$ds pool_meta $pool]

		set row	{}
		foreach f $olditem h $hdrs {
			lappend row $h	$f
		}

		try {
			if {![expr $filter]} return
		} on error {errmsg options} {
			throw_error [list filter_error $errmsg] "Error applying filter ($filter): $errmsg"
		}

		set use_trans	[expr {$translator ne {}}]

		if {$use_trans} $translator

		if {$use_trans} {
			set old_outrow	{}
			foreach h $last_headers {
				lappend old_outrow	[dict get $row $h]
			}
		} else {
			set old_outrow	$olditem
		}
		set old_id		[lindex $old_outrow $id_column]

		set damp_onchange	0
		my invoke_handlers remove_item $pool $old_id $old_outrow
	}

	#>>>
	method _new_pool {pool} { #<<<
		$dominos(need_refilter) tip
		set damp_onchange	0
		my invoke_handlers new_pool $pool
	}

	#>>>
	method _remove_pool {pool} { #<<<
		$dominos(need_refilter) tip
		set damp_onchange	0
		my invoke_handlers remove_pool $pool
	}

	#>>>
	method _get_compose_info {{criteria {}}} { #<<<
		# returns { base_data composite_filters composite_translators headers custom_keys}

		set filters		{}
		set translators	{}
		set custom_key_dicts	{}
		set override_headers_list	{}
		set ds_now		$this
		while {$ds_now ne {}} {
			lappend ds_stack	$ds_now
			if {![info object isa object $ds_now]} {
				error "Can't examine parent datasource: \"$ds_now\": not an object"
			}
			switch -- [info object class $ds_now] {
				"::ds::datasource_filter" {
					set filter		[$ds_now cget -filter]
					set translator	[$ds_now cget -translator]

					lappend filters	$filter
					lappend translators	$translator
					lappend custom_key_dicts	[$ds_now get_custom_key_dict]
					lappend override_headers_list	[$ds_now cget -override_headers]

					set ds_now		[$ds_now cget -ds]
				}

				"::ds::dschan" {
					set base_data	[$ds_now get_list_extended $criteria headers]
					set ds_now		{}
				}

				"::ds::dslist" {
					set base_data	[list {} [list {} [$ds_now get_list $criteria headers]]]
					set ds_now		{}
				}

				default {
					error "Can't compose parent datasource \"$ds_now\": type \"[info object class $ds_now]\" not supported"
				}
			}
		}

		set custom_keys	[dict merge {*}[lreverse $custom_key_dicts]]
		list $base_data [lreverse $filters] [lreverse $translators] $headers $custom_keys [lreverse $override_headers_list]
	}

	#>>>
}


