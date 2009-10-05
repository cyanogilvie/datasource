# vim: foldmethod=marker foldmarker=<<<,>>> ft=tcl ts=4 shiftwidth=4

cflib::pclass create ds::dschan_backend_list {
	superclass cflib::baselog

	property id_column		0	_id_column_changed
	property comp			""
	property tag			""
	property headers		{}	_headers_changed

	variable {*}{
		auth
		pools
		pool_data
		pool_jmids
		general_info_jmid
	}

	constructor {args} { #<<<
		set pools		[dict create]
		set pool_data	[dict create]
		set pool_jmids	[dict create]
		
		my configure {*}$args

		foreach reqf {comp tag headers} {
			if {[set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		set auth	[$comp cget -auth]
		$comp handler $tag [my code _req_handler]
	}

	#>>>

	method _headers_changed {} { #<<<
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list headers_changed $headers]
		}
	}

	#>>>
	method _id_column_changed {} { #<<<
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list id_column_changed $id_column]
		}
	}

	#>>>

	method register_pool {pool {check_cb {}}} { #<<<
		dict set pools $pool		$check_cb
		dict set pool_data $pool	{}
		my log debug "registered pool"
		my _announce_pool $pool
	}

	#>>>
	method deregister_pool {pool} { #<<<
		my _check_pool $pool
		if {[dict exists $pool_jmids $pool]} {
			$auth jm_can [dict get $pool_jmids $pool] [list pool_deregistered]
			$auth chans deregister_chan [dict get $pool_jmids $pool]
		}
		dict unset pool_jmids $pool
		dict unset pool_data $pool
		dict unset pools $pool
		my log debug "deregistered pool"
	}

	#>>>
	method add_item {pool item} { #<<<
		my _check_pool $pool
		set id		[lindex $item $id_column]
		
		set idx		[my _scan_for_id $pool $id]
		if {$idx != -1} {
			error "ID \"$id\" already exists in ($pool), adding ([join $item |])"
		}
		dict lappend pool_data $pool	$item

		my log debug "announcing new item ($id) in pool ($pool)"
		my _announce_new $pool $id $item
	}

	#>>>
	method change_item {pool id newitem} { #<<<
		my _check_pool $pool
		set idx		[my _scan_for_id $pool $id]
		if {$idx == -1} {
			error "ID $id does not exist in $pool"
		}

		set olditem				[lindex [dict get $pool_data $pool] $idx]
		dict set pool_data $pool \
				[lreplace [dict get $pool_data $pool] $idx $idx $newitem]
		my log debug "\nannouncing item change ($id) in pool ($pool)\nold: ($olditem)\nnew: ($newitem)"
		my _announce_changed $pool $id $olditem $newitem
	}

	#>>>
	method remove_item {pool id} { #<<<
		my _check_pool $pool
		set idx		[my _scan_for_id $pool $id]
		if {$idx != -1} {
			set item				[lindex [dict get $pool_data $pool] $idx]
			dict set pool_data $pool \
					[lreplace [dict get $pool_data $pool] $idx $idx]
			my log debug "announcing item removal ($id) from pool ($pool)"
			my _announce_removed $pool $id $item
		} else {
			my log warning "item ($id) not found in pool ($pool)"
		}
	}

	#>>>
	method get_item {pool id} { #<<<
		my _check_pool $pool
		set idx		[my _scan_for_id $pool $id]
		if {$idx == -1} {
			error "ID $id does not exist in $pool"
		}
		lindex [dict get $pool_data $pool] $idx
	}

	#>>>
	method item_count {pool} { #<<<
		my _check_pool $pool
		llength [dict get $pool_data $pool]
	}

	#>>>
	method id_list {pool} { #<<<
		my _check_pool $pool
		set ids	{}
		foreach item [dict get $pool_data $pool] {
			lappend ids [lindex $item $id_column]
		}
		return $ids
	}

	#>>>
	method pool_exists {pool} { #<<<
		dict exists $pools $pool
	}

	#>>>
	method start_init {} { #<<<
	}

	#>>>
	method end_init {} { #<<<
	}

	#>>>
	method abort_init {} { #<<<
	}

	#>>>

	method _announce_pool {pool} { #<<<
		my log debug "general_info_jmid exists: [info exists general_info_jmid]"
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list new_pool $pool]
		}
	}

	#>>>
	method _announce_new {pool id item} { #<<<
		my log debug "pool exists: [dict exists $pool_jmids $pool]]"
		if {[dict exists $pool_jmids $pool]} {
			$auth jm [dict get $pool_jmids $pool] [list new $id $item]
		}
	}

	#>>>
	method _announce_changed {pool id olditem newitem} { #<<<
		my log debug "pool exists: [dict exists $pool_jmids $pool]]"
		if {[dict exists $pool_jmids $pool]} {
			$auth jm [dict get $pool_jmids $pool] [list changed $id $olditem $newitem]
		}
	}

	#>>>
	method _announce_removed {pool id item} { #<<<
		my log debug "pool exists: [dict exists $pool_jmids $pool]]"
		if {[dict exists $pool_jmids $pool]} {
			$auth jm [dict get $pool_jmids $pool] [list removed $id $item]
		}
	}

	#>>>
	method _check_pool {pool} { #<<<
		if {![dict exists $pools $pool]} {
			throw [list no_pool $pool] "No such pool: ($pool)"
		}
	}

	#>>>
	method _scan_for_id {pool id} { #<<<
		lsearch -index $id_column [dict get $pool_data $pool] $id
	}

	#>>>
	method _req_handler {auth user seq rest} { #<<<
		switch -- [lindex $rest 0] {
			"setup_chans" { #<<<
				set extra	[lindex $rest 1]

				set userpools	{}
				dict for {pool check_cb} $pools {
					try {
						# Provide a place for the check_cb callback to scribble into
						# via an upvar command.  We send the contents to the client
						array unset pool_meta
						array set pool_meta {}

						my log debug "check_cb is: ($check_cb)"
						if {
							$check_cb eq {} ||
							[{*}$check_cb $user $pool $extra]
						} {
							lappend userpools	$pool
						}

						set pool_meta_all($pool)	[array get pool_meta]
						my log debug "Saving pool_meta for ($pool):\n$pool_meta_all($pool)"
					} on error {errmsg options} {
						my log error "error calling check_cb:\n[dict get $options -errorinfo]"
					}
				}

				if {![info exists general_info_jmid]} {
					set general_info_jmid	[$auth unique_id]
					$auth chans register_chan $general_info_jmid \
							[my code _general_info_chan_cb]
				}
				$auth pr_jm $general_info_jmid $seq [list general [list \
						headers		$headers \
						id_column	$id_column \
				]]

				foreach pool $userpools {
					if {![dict exists $pool_jmids $pool]} {
						dict set pool_jmids $pool	[$auth unique_id]
						$auth chans register_chan [dict get $pool_jmids $pool] \
								[my code _pool_chan_cb $pool]
					}

					my log debug "Contents of pool_meta array:\n[array get pool_meta]"
					$auth pr_jm [dict get $pool_jmids $pool] $seq [list datachan $pool [dict get $pool_data $pool] $pool_meta_all($pool)]
				}

				$auth ack $seq ""
				#>>>
			}
			"setup_new_pool" { #<<<
				lassign $rest - new_pool extra

				if {![dict exists $pools $new_pool]} {
					$auth nack $seq "No such pool: ($new_pool)"
					return
				}
				set check_cb	[dict get $pools $new_pool]
				try {
					# Provide a place for the check_cb callback to scribble into
					# via an upvar command.  We send the contents to the client
					array set pool_meta {}

					if {
						$check_cb eq {} ||
						[{*}$check_cb $user $new_pool $extra]
					} {
						if {![dict exists $pool_jmids $new_pool]} {
							dict set pool_jmids $new_pool	[$auth unique_id]
							$auth chans register_chan \
									[dict get $pool_jmids $new_pool] \
									[my code _pool_chan_cb $new_pool]
						}

						$auth pr_jm [dict get $pool_jmids $new_pool] $seq [list datachan $new_pool [dict get $pool_data $new_pool] [array get pool_meta]]
						my log debug "Added user ([$user name]) to new pool ($new_pool)"

						$auth ack $seq ""
					} else {
						my log debug "User ([$user name]) is not a viewer of pool ($new_pool)"
						$auth ack $seq ""
					}
				} on error {errmsg options} {
					my log error "error calling check_cb:\n[dict get $options -errorinfo]"
					$auth nack $seq "Internal error"
					return
				}
				#>>>
			}
			default { #<<<
				my log error "invalid req type: [lindex $rest 0]"
				$auth nack $seq "Invalid req type: ([lindex $rest 0])"
				#>>>
			}
		}
	}

	#>>>
	method _pool_chan_cb {pool op data} { #<<<
		switch -- $op {
			cancelled {
				my log debug "all destinations disconnected"
				dict unset pool_jmids $pool
			}

			req {
				lassign $data seq prev_seq msg
				$auth nack $seq "Requests not allowed on this channel"
			}

			default {
				my log error "unexpected op: ($op)"
			}
		}
	}

	#>>>
	method _general_info_chan_cb {op data} { #<<<
		switch -- $op {
			cancelled {
				my log debug "all destinations disconnected"
				if {[info exists general_info_jmid]} {
					unset general_info_jmid
				}
			}

			req {
				lassign $data seq prev_seq msg
				$auth nack $seq "Requests not allowed on this channel"
			}

			default {
				my log error "unexpected op: ($op)"
			}
		}
	}

	#>>>
}


