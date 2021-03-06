# vim: foldmethod=marker foldmarker=<<<,>>> ft=tcl ts=4 shiftwidth=4

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

# Datasource client-side pool cache:
#
# The idea is to cache the pool data in a sqlite database in the client
# side persistently and have this class initialize itself from this on
# construction.  Then we synchronize with the backend, arrange for the
# list of pool members that should be deleted, and all modifications 
# (changes and additions) that occurred since our last applied update,
# and all new / removed pools, and apply them locally.  This should amount to a
# substantial network bandwidth saving.
#
# Note that last_updated is the server time (supplied with the update packets)
#
# create table pool_data (
#	id				integer primary key,
#	tag				text not null,
#	pool			text not null,
#	last_updated	integer not null,
#	itemdata		text not null
# );
#
# create table pool_last_update (
#	tag				text not null,
#	pool			text not null,
#	last_updated	integer not null
# );
#

#oo::class create ds::tclass {
#	superclass cflib::pclass
#
#	method new args {
#		tailcall my create ::ds::inst_dschan_[incr ::ds::instseq] {*}$args
#	}
#}
#ds::tclass create ds::dschan

cflib::pclass create ds::dschan {
	superclass sop::signalsource ds::datasource

	property connector
	property tag		""			_tag_changed
	property extra		""
	property dbfile		""
	property dbtable	"pool_data"

	variable {*}{
		dominos
		general
		pool_data
		pool_meta
		pool_jmids
		jmid2pool
		general_jmid
	}

	constructor {args} { #<<<
		?? {log debug "Constructing dschan [self]"}
		package require m2

		set general		[dict create]
		set pool_data	[dict create]
		set pool_meta	[dict create]
		set pool_jmids	[dict create]
		set jmid2pool	[dict create]

		array set dominos			{}
		dict set general headers	{""}

		sop::domino new dominos(need_refresh) -name "[self] need_refresh"
		$dominos(need_refresh) attach_output [my code _signal_refresh]
		sop::signal new signals(connected) -name "[self] connected"

		?? {
			$signals(connected) attach_output [list apply {
				{obj newstate} {log debug "dschan $obj connected: $newstate"}
			} [self]]
		}

		my configure {*}$args

		foreach reqf {connector tag} {
			if {![info exists $reqf] || [set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		[$connector signal_ref authenticated] attach_output \
				[my code _authenticated_changed]
		?? {log debug "Finished constructing dschan [self]"}
	}

	#>>>
	destructor { #<<<
		if {
			[info exists connector] &&
			[info object isa object $connector]
		} {
			if {[info exists general_jmid]} {
				[$connector auth] jm_disconnect {*}$general_jmid
				unset general_jmid
			}
			dict for {pool jm} $pool_jmids {
				[$connector auth] jm_disconnect {*}$jm
			}
			set pool_jmids	{}
			[$connector signal_ref authenticated] detach_output \
					[my code _authenticated_changed]
		}
	}

	#>>>

	method _tag_changed {} { #<<<
		set baselog_instancename	$tag
	}

	#>>>

	method get_list {a_criteria {headersvar {}}} { #<<<
		if {$headersvar ne {}} {
			upvar $headersvar h
			set h	[dict get $general headers]
		}

		set last_headers [dict get $general headers]

		set list	[dict values $pool_data]

		?? {log debug "dschan [self] get_list headers: ($last_headers)"}
		set flatlist	[concat {*}$list]
		lsort -unique -index $id_column $flatlist
	}

	#>>>
	method get_list_extended {a_criteria {headersvar {}}} { #<<<
		if {$headersvar ne {}} {
			upvar $headersvar h
			set h	[dict get $general headers]
		}

		set last_headers [dict get $general headers]

		list $pool_meta $pool_data
	}

	#>>>
	method get_headers {} { #<<<
		dict get $general headers
	}

	#>>>
	method pool_meta {pool} { #<<<
		if {![dict exists $pool_meta $pool]} {
			throw [list invalid_pool $pool] "Invalid pool: $pool"
		}

		dict get $pool_meta $pool
	}

	#>>>
	method add_item {item} { #<<<
		if {![my can_do insert]} {
			error "insert not supported"
		}
		$connector req $tag [list add $item]
	}

	#>>>
	method update_item {olditem newitem} { #<<<
		if {![my can_do update]} {
			error "update not supported"
		}
		$connector req $tag [list update $olditem $newitem]
	}

	#>>>
	method remove_item {item} { #<<<
		if {![my can_do delete]} {
			error "delete not supported"
		}
		$connector req $tag [list remove $item]
	}

	#>>>

	method _authenticated_changed {newstate} { #<<<
		?? {log debug "dschan [self] authenticated_changed: $newstate"}
		if {$newstate} {
			#log debug "Attempting to setup chans extra: ($extra)"
			?? {log debug "Datasource_chan [self] requesting setup_chans"}
			$connector req_async $tag [list "setup_chans" $extra] \
					[my code _jm_handler [list initial]]
		} else {
			#log error "not connected to backend"
			$signals(connected) set_state 0
		}
	}

	#>>>
	method _jm_handler {context msg} { #<<<
		?? {log debug "dschan::_jm_handler context: ($context), msg: [dict get $msg type]"}
		switch -- [dict get $msg type] {
			ack { #<<<
				set cdata	[lassign $context type]
				switch -- $type {
					"new_pool" {
						lassign $cdata new_pool
						#log debug "joined new pool ($new_pool), invoking new_pool handlers"
						?? {log debug "Datasource_chan [self] setup new pool returned ($new_pool)"}
						my invoke_handlers new_pool $new_pool
					}

					"initial" {
						lassign $cdata extra
						#log debug "Setup chans returned.  extra: ($extra)"
						?? {log debug "Datasource_chan [self] setup_chans ack, extra: ($extra)"}
						$signals(connected) set_state 1
						my invoke_handlers init
					}

					default {
						log error "Ack for unexpected context: ($type)"
					}
				}
				#>>>
			}
			nack { #<<<
				set cdata	[lassign $context type]
				switch -- $type {
					"new_pool" {
						lassign $cdata new_pool
						log error "error calling setup_new_pool ($new_pool): [dict get $msg data]"
					}

					"initial" {
						log error "error calling setup_chans: ([dict get $msg data])"
					}

					default {
						log error "Nack for unexpected context: ([dict get $msg type])"
					}
				}
				#>>>
			}
			pr_jm { #<<<
				?? {log debug "dschan _jm_handler/pr_jm([dict get $msg seq]): type [lindex [dict get $msg data] 0]"}
				switch -- [lindex [dict get $msg data] 0] {
					"general" {
						my variable can_do
						set general_jmid	[list [dict get $msg seq] [dict get $msg prev_seq]]
						set general			[dict merge {
							capabilities	{lookup}
						} [lindex [dict get $msg data] 1]]
						set id_column		[dict get $general id_column]
						foreach cap [dict keys $can_do] {
							if {$cap ni [dict get $general capabilities]} {
								my can_do $cap no
							}
						}
						foreach cap [dict get $general capabilities] {
							my can_do $cap yes
						}
						$dominos(need_refresh) tip
					}

					"datachan" {
						lassign [dict get $msg data] - pool data meta
						?? {log debug "dschan _jm_handler/pr_jm([dict get $msg seq]) got datachan setup for pool: \"$pool\""}
						dict set pool_data $pool	$data
						dict set pool_meta $pool	$meta
						dict set pool_jmids $pool	[list [dict get $msg seq] [dict get $msg prev_seq]]
						dict set jmid2pool [dict get $msg seq]	$pool
						$dominos(need_refresh) tip
					}

					default {
						log error "unrecognized pr_jm type: ([lindex [dict get $msg data] 0])"
					}
				}
				#>>>
			}
			jm { #<<<
				if {![dict exists $jmid2pool [dict get $msg seq]]} {
					if {
						[info exists general_jmid] &&
						[dict get $msg seq] eq [lindex $general_jmid 0]
					} {
						#log debug "general info update"
						switch -- [lindex [dict get $msg data] 0] {
							"headers_changed" { #<<<
								dict set general headers	[lindex [dict get $msg data] 1]
								my invoke_handlers headers_changed [dict get $general headers]
								$dominos(need_refresh) tip
								#>>>
							}
							"id_column_changed" { #<<<
								dict set general id_column	[lindex [dict get $msg data] 1]
								set id_column		[dict get $general $id_column]
								my invoke_handlers id_column_changed $id_column
								$dominos(need_refresh) tip
								#>>>
							}
							"new_pool" { #<<<
								set new_pool			[lindex [dict get $msg data] 1]
								#log debug "received notice of new pool: ($new_pool), requesting to join (extra: $extra)"
								?? {log debug "Datasource_chan [self] received notice of new pool: ($new_pool), requesting to join (extra: $extra)"}
								$connector req_async $tag \
										[list "setup_new_pool" $new_pool $extra] \
										[my code _jm_handler [list new_pool [list $new_pool]]]
								#>>>
							}
							default { #<<<
								log error "unknown general info update type: ([lindex [dict get $msg data] 0])"
								#>>>
							}
						}
					} else {
						log error "dschan::_jm_handler/jm: unrecognized channel: ([dict get $msg seq])"
						?? {
							log error "general chan: [lindex $general_jmid 0]"
							dict for {jmid pool} $jmid2pool {
								log error "pooljmid $jmid -> \"$pool\""
							}
						}
					}
				} else {
					set pool	[dict get $jmid2pool [dict get $msg seq]]
					switch -- [lindex [dict get $msg data] 0] {
						"new" { #<<<
							lassign [dict get $msg data] - id item

							dict lappend pool_data $pool	$item

							try {
								my invoke_handlers new_item $pool $id $item
							} on error {errmsg options} {
								log error "handlers for new_item threw error: $errmsg\n[dict get $options -errorinfo]"
							} on ok {} {
								?? {log debug "All handlers for new_item completed ok"}
							}
							$dominos(need_refresh) tip
							#>>>
						}
						"changed" { #<<<
							lassign [dict get $msg data] - id olditem newitem
							set idx		[my _scan_for_id $pool $id]
							if {$idx == -1} {
								log error "changed: couldn't find id ($id)"
							} else {
								dict set pool_data $pool	[lreplace [dict get $pool_data $pool] $idx $idx $newitem]
								my invoke_handlers change_item $pool $id $olditem $newitem
								$dominos(need_refresh) tip
							}
							#>>>
						}
						"removed" { #<<<
							lassign [dict get $msg data] - id olditem
							set idx		[my _scan_for_id $pool $id]
							if {$idx == -1} {
								log error "removed: couldn't find id ($id)"
							} else {
								dict set pool_data $pool	[lreplace [dict get $pool_data $pool] $idx $idx]
								my invoke_handlers remove_item $pool $id $olditem
								$dominos(need_refresh) tip
							}
							#>>>
						}
						default { #<<<
							log error "unhandled update type: ([lindex [dict get $msg data] 0])"
							#>>>
						}
					}
				}
				#>>>
			}
			jm_can { #<<<
				if {![dict exists $jmid2pool [dict get $msg seq]]} {
					if {
						[info exists general_jmid] &&
						[dict get $msg seq] eq [lindex $general_jmid 0]
					} {
						my variable can_do
						foreach cap [dict keys $can_do] {
							if {$cap ni {lookup}} {
								my can_do $cap no
							}
						}
						unset general_jmid
						$signals(connected) set_state 0
					} else {
						log error "unrecognized channel cancelled: ([dict get $msg seq])"
					}
				} else {
					set pool	[dict get $jmid2pool [dict get $msg seq]]
					dict unset jmid2pool	[dict get $msg seq]
					dict unset pool_data	$pool
					dict unset pool_meta	$pool
					dict unset pool_jmids	$pool

					my invoke_handlers remove_pool $pool
					$dominos(need_refresh) tip
				}
				#>>>
			}
			default { #<<<
				log error "unexpected type: ([dict get $msg type])"
				#>>>
			}
		}
	}

	#>>>
	method _signal_refresh {} { #<<<
		my invoke_handlers onchange
	}

	#>>>
	method _scan_for_id {pool id} { #<<<
		lsearch -index $id_column [dict get $pool_data $pool] $id
	}

	#>>>
}


