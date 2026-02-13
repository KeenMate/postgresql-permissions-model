alter database postgresql_permissionmodel set search_path to public, const, ext, stage, helpers, internal, unsecure, auth, triggers;
alter role postgresql_permissionmodel set search_path to public, const, ext, stage, helpers, internal, unsecure, auth, triggers;
alter role postgres set search_path to public, const, ext, stage, helpers, internal, unsecure, auth, triggers;
set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

/***
 *    ██████╗ ██████╗     ██████╗ ███████╗██████╗ ███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
 *    ██╔══██╗██╔══██╗    ██╔══██╗██╔════╝██╔══██╗████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
 *    ██║  ██║██████╔╝    ██████╔╝█████╗  ██████╔╝██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
 *    ██║  ██║██╔══██╗    ██╔═══╝ ██╔══╝  ██╔══██╗██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
 *    ██████╔╝██████╔╝    ██║     ███████╗██║  ██║██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║███████║
 *    ╚═════╝ ╚═════╝     ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
 *
 */

grant select, insert, update, truncate, delete on all tables in schema const, unsecure, error, ext, auth, helpers, internal, stage, triggers, public to postgresql_permissionmodel;

grant usage on schema const, unsecure, error, ext, auth, helpers, internal, stage, triggers, public to postgresql_permissionmodel;
grant usage, select on all sequences in schema const, unsecure, error, ext, auth, helpers, internal, stage, triggers, public to postgresql_permissionmodel;

do
$$
	declare
		__owner     text;
		__new_owner text;
		__cmd       text;
	begin

		__new_owner := 'postgresql_permissionmodel';

		for __owner in (select owner
										from (select distinct tableowner as owner
													from pg_tables
													where schemaname in
																('auth', 'const', 'error', 'helpers', 'triggers', 'internal', 'public',
																 'stage', 'unsecure')
													union
													select viewowner
													from pg_views
													where schemaname in
																('auth', 'const', 'error', 'helpers', 'triggers', 'internal', 'public',
																 'stage', 'unsecure')
													union
													select sequenceowner
													from pg_sequences
													where schemaname in
																('auth', 'const', 'error', 'helpers', 'triggers', 'internal', 'public',
																 'stage', 'unsecure')
													union
													select u.usename
													from pg_proc p
																 inner join pg_user u on p.proowner = u.usesysid
																 inner join pg_namespace pn on p.pronamespace = pn.oid
													where pn.nspname in
																('auth', 'const', 'error', 'helpers', 'triggers', 'internal', 'public',
																 'stage', 'unsecure')
													group by u.usename) as __owners
										where owner not in ('postgres', __new_owner))
			loop
				__cmd := format('REASSIGN OWNED BY %s TO %s', __owner, __new_owner);
				raise notice '%', __cmd;

				execute __cmd;

			end loop;
	end;
$$;
