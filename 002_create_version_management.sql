/***
 *    ██████╗  █████╗ ████████╗ █████╗ ██████╗  █████╗ ███████╗███████╗    ██╗   ██╗███████╗██████╗ ███████╗██╗ ██████╗ ███╗   ██╗
 *    ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝    ██║   ██║██╔════╝██╔══██╗██╔════╝██║██╔═══██╗████╗  ██║
 *    ██║  ██║███████║   ██║   ███████║██████╔╝███████║███████╗█████╗      ██║   ██║█████╗  ██████╔╝███████╗██║██║   ██║██╔██╗ ██║
 *    ██║  ██║██╔══██║   ██║   ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝      ╚██╗ ██╔╝██╔══╝  ██╔══██╗╚════██║██║██║   ██║██║╚██╗██║
 *    ██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝██║  ██║███████║███████╗     ╚████╔╝ ███████╗██║  ██║███████║██║╚██████╔╝██║ ╚████║
 *    ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝      ╚═══╝  ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
 *
 */
set search_path = public, const, ext, stage, helpers, internal, unsecure;

create table __version
(
	version_id         int generated always as identity not null primary key,
	component          text                             not null default 'main',
	version            text                             not null,
	title              text                             not null,
	description        text,
	execution_started  timestamptz                      not null default now(),
	execution_finished timestamptz
);

create unique index uq_version on __version (component, version);

create function start_version_update(_version text, _title text, _description text default null,
																		 _component text default 'main')
	returns table(
		__version_id         integer,
		__component          text,
		__version            text,
		__title              text,
		__description        text,
		__execution_started  timestamptz,
		__execution_finished timestamptz
	)
	language sql
as
$$

insert into __version(component, version, title, description)
VALUES (_component, _version, _title, _description)
returning version_id, component, version, title, description, execution_started, execution_finished;

$$;

create function stop_version_update(_version text, _component text default 'main')
	returns table(
		__version_id         integer,
		__component          text,
		__version            text,
		__title              text,
		__description        text,
		__execution_started  timestamptz,
		__execution_finished timestamptz
	)
	language sql
as
$$

update __version
set execution_finished = now()
where component = _component
	and version = _version
returning version_id, component, version, title, description, execution_started, execution_finished;

$$;

create function check_version(_version text, _component text default 'main')
	returns bool
	language sql
	cost 1
as
$$
select exists(select
							from __version
							where component = _component
								and version = _version);

$$;