/***
 *    ███████╗██╗    ██╗██╗████████╗ ██████╗██╗  ██╗    ███████╗ ██████╗██╗  ██╗███████╗███╗   ███╗ █████╗
 *    ██╔════╝██║    ██║██║╚══██╔══╝██╔════╝██║  ██║    ██╔════╝██╔════╝██║  ██║██╔════╝████╗ ████║██╔══██╗
 *    ███████╗██║ █╗ ██║██║   ██║   ██║     ███████║    ███████╗██║     ███████║█████╗  ██╔████╔██║███████║
 *    ╚════██║██║███╗██║██║   ██║   ██║     ██╔══██║    ╚════██║██║     ██╔══██║██╔══╝  ██║╚██╔╝██║██╔══██║
 *    ███████║╚███╔███╔╝██║   ██║   ╚██████╗██║  ██║    ███████║╚██████╗██║  ██║███████╗██║ ╚═╝ ██║██║  ██║
 *    ╚══════╝ ╚══╝╚══╝ ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝
 *
 *    TO km_common_helpers database
 */

create schema if not exists error;
create schema if not exists const;
create schema if not exists internal;
create schema if not exists unsecure; -- functions without any permission validation
create schema if not exists helpers;
create schema if not exists ext;
create schema if not exists auth;


create extension if not exists pg_trgm schema ext;
