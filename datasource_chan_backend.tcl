# vim: foldmethod=marker foldmarker=<<<,>>> ft=tcl ts=4 shiftwidth=4

# TODO:
# 	Periodic housecleaning routine for recently_deceased trimming

cflib::pclass create ds::dschan_backend {
	superclass cflib::baselog

	property id_column		0	_id_column_changed
	property comp			""	_comp_changed
	property tag
	property headers		{}	_headers_changed
	property dbfile			":memory:"
	property persist		0

	variable {*}{
		auth
		pools
		pool_jmids
		general_info_jmid
		db
		_dbfile
		in_init_transaction
	}

	constructor {args} { #<<<
		package require sqlite3

		set in_init_transaction	0
		set pools		[dict create]
		set pool_jmids	[dict create]

		my configure {*}$args

		foreach reqf {comp tag headers} {
			if {![info exists $reqf] || [set $reqf] eq ""} {
				error "Must set -$reqf"
			}
		}

		# Canonise dbfile <<<
		if {$dbfile eq ":memory:" || $dbfile eq ""} {
			set _dbfile		":memory:"
		} else {
			if {![file exists $dbfile]} {
				set file_hack	1
				set fp	[open $dbfile w]
				close $fp
			}
			set _dbfile	[cflib::fullynormalize $dbfile]

			if {[info exists file_hack]} {
				file delete $_dbfile
			}
		}
		# Canonise dbfile >>>

		set db		"db,[self]"
		sqlite3 [namespace current]::$db $_dbfile

		my _init_db

		set auth	[$comp cget -auth]
		$comp handler $tag [my code _req_handler]
	}

	#>>>
	destructor { #<<<
		if {[info exists db]} {
			$db close
			unset db
			if {!($persist) && $_dbfile ne ":memory:"} {
				if {[file exists $_dbname]} {
					file delete $_dbname
				}
			}
		}
	}

	#>>>

	method _id_column_changed {} { #<<<
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list id_column_changed $id_column]
		}
	}

	#>>>
	method _headers_changed {} { #<<<
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list headers_changed $headers]
		}
	}

	#>>>
	method _comp_changed {} { #<<<
		if {[info exists pool] && [info exists check_cb]} {
			dict set pools $pool		$check_cb
			my _announce_pool $pool
		}
	}

	#>>>

	method register_pool {pool {check_cb {}}} { #<<<
		dict set pools $pool $check_cb
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
		$db eval {
			delete from
				pool_data
			where
				pool = $pool
		}
		dict unset pools $pool
	}

	#>>>
	method add_item {pool item} { #<<<
		my _check_pool $pool
		set id		[lindex $item $id_column]

		if {[my id_exists $pool $id]} {
			throw [list duplicate_id $id $pool] \
					"ID \"$id\" already exists in ($pool), adding ([join $item |])"
		}
		set last_updated	[clock seconds]
		$db eval {
			insert into pool_data (
				pool,
				id,
				last_updated,
				data
			) values (
				$pool,
				$id,
				$last_updated,
				$item
			)
		}

		my _announce_new $pool $id $item
	}

	#>>>
	method change_item {pool id newitem} { #<<<
		my _check_pool $pool

		if {![my id_exists $pool $id]} {
			error "ID $id does not exist in $pool"
		}

		set newid	[lindex $newitem $id_column]
		if {$newid ne $id} {
			throw [list id_column_changed $id $newid] \
					"Changing id column not allowed"
		}

		set olditem			[my get_item $pool $id]
		if {$olditem eq $newitem} return

		set last_updated	[clock seconds]
		$db eval {
			update
				pool_data
			set
				data = $newitem,
				last_updated = $last_updated
			where
				id = $id
				and pool = $pool
		}
		my _announce_changed $pool $id $olditem $newitem
	}

	#>>>
	method remove_item {pool id} { #<<<
		my _check_pool $pool
		if {![my id_exists $pool $id]} {
			my log warning "item ($id) not found in pool ($pool)"
			return
		}

		set item		[my get_item $pool $id]
		if {!($in_init_transaction)} {
			$db eval {begin}
		}
		try {
			set dbid	[$db onecolumn {
				select
					autoid
				from
					pool_data
				where
					id = $id
					and pool = $pool
			}]
			$db eval {
				delete from
					pool_data
				where
					id = $id
					and pool = $pool
			}
			set timeofdeath	[clock seconds]
			$db eval {
				insert into recently_deceased (
					dbid,
					timeofdeath
				) values (
					$dbid,
					$timeofdeath
				)
			}
		} on ok {} {
			if {!($in_init_transaction)} {
				$db eval {commit}
			}
		} on error {errmsg options} {
			$db eval {rollback}
			return -options $options $errmsg
		}
		my _announce_removed $pool $id $item
	}

	#>>>
	method get_item {pool id} { #<<<
		my _check_pool $pool
		set rows	[$db eval {
			select
				data
			from
				pool_data
			where
				id = $id
				and pool = $pool
		}]
		# WARNING: this logic will break if more columns are selected
		if {[llength $rows] == 0} {
			error "ID $id does not exist in $pool"
		}
		if {[llength $rows] > 1} {
			my log warning "Duplicate rows for id ($id) and pool ($pool)"
		}
		lindex $rows 0
	}

	#>>>
	method item_count {pool} { #<<<
		my _check_pool $pool
		$db onecolumn {
			select
				count(1)
			from
				pool_data
			where
				pool = $pool
		}
	}

	#>>>
	method id_list {pool} { #<<<
		my _check_pool $pool
		$db eval {
			select
				id
			from
				pool_data
			where
				pool = $pool
		}
	}

	#>>>
	method pool_exists {pool} { #<<<
		dict exists $pools $pool
	}

	#>>>
	method id_exists {pool id} { #<<<
		$db onecolumn {
			select
				count(1) > 0
			from
				pool_data
			where
				pool = $pool
				and id = $id
		}
	}

	#>>>
	method start_init {} { #<<<
		$db eval {begin}
		set in_init_transaction	1
	}

	#>>>
	method end_init {} { #<<<
		$db eval {commit; analyze}
		set in_init_transaction	0
	}

	#>>>
	method abort_init {} { #<<<
		$db eval {rollback}
		set in_init_transaction	0
	}

	#>>>

	method _announce_pool {pool} { #<<<
		if {[info exists general_info_jmid]} {
			$auth jm $general_info_jmid [list new_pool $pool]
		}
	}

	#>>>
	method _announce_new {pool id item} { #<<<
		if {[dict exists $pool_jmids $pool]} {
			$auth jm [dict get $pool_jmids $pool] [list new $id $item]
		}
	}

	#>>>
	method _announce_changed {pool id olditem newitem} { #<<<
		if {[dict exists $pool_jmids $pool]} {
			$auth jm [dict get $pool_jmids $pool] \
					[list changed $id $olditem $newitem]
		}
	}

	#>>>
	method _announce_removed {pool id item} { #<<<
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
	method _req_handler {auth user seq rest} { #<<<
		switch -- [lindex $rest 0] {
			"setup_chans" { #<<<
				set extra	[lindex $rest 1]

				set userpools	{}
				dict for {pool check_cb} $pools {
					try {
						# Provide a place for the check_cb callback to scribble into
						# via an upvar command.  We send the contents to the client
						set pool_meta	[dict create]

						if {
							$check_cb eq {} ||
							[{*}$check_cb $user $pool $extra]
						} {
							lappend userpools	$pool
						}

						dict set pool_meta_all $pool	$pool_meta
					} on error {errmsg options} {
						my log error "error calling check_cb:\n$::errorInfo"
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
						$auth chans register_chan \
								[dict get $pool_jmids $pool] \
								[my code _pool_chan_cb $pool]
					}

					set all_items	[$db eval {
						select
							data
						from
							pool_data
						where
							pool = $pool
					}]
					$auth pr_jm [dict get $pool_jmids $pool] $seq \
							[list datachan $pool $all_items [dict get $pool_meta_all $pool]]
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
					set pool_meta	[dict create]

					if {
						$check_cb eq {}
						|| [{*}$check_cb $user $new_pool $extra]
					} {
						if {![dict exists $pool_jmids $new_pool]} {
							dict set pool_jmids $new_pool	[$auth unique_id]
							$auth chans register_chan \
									[dict get $pool_jmids $new_pool] \
									[my code _pool_chan_cb $new_pool]
						}

						set all_items	[$db eval {
							select
								data
							from
								pool_data
							where
								pool = $new_pool
						}]
						$auth pr_jm [dict get $pool_jmids $new_pool] $seq \
								[list datachan $new_pool $all_items $pool_meta]

						$auth ack $seq ""
					} else {
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
	method _init_db {} { #<<<
		set exists	[$db onecolumn {
			select
				count(1) > 0
			from
				sqlite_master
			where
				type = 'table'
				and name = 'pool_data'
		}]

		if {!($persist) && $exists} {
			$db eval {
				drop table pool_data;
				drop table recently_deceased;
			}
			set exists	0
		}

		# recently_deceased.dbid == -1 gives the last cleanout time
		if {!($exists)} {
			$db eval {
				create table pool_data (
					autoid			integer primary key autoincrement,
					pool			text,
					id				text,
					last_updated	integer,
					data			text
				);
				create index pool_data_pool_idx on pool_data(pool);
				create index pool_data_id_idx on pool_data(id);

				create table recently_deceased (
					dbid			integer not null,
					timeofdeath		integer not null
				);
				create index recently_deceased_timeofdeath_idx 
					on recently_deceased(timeofdeath);
			}
		}
	}

	#>>>
}


