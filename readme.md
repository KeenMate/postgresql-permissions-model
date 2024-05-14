# postgresql-permission-model

This is our PostgreSQL database model for everything related to users/groups/permissions and permission sets.

It's not a absolutely complete solution but we use it already in many real life projects, big and small.

## Main features

The database is able to keep records of users and groups, keep their memberships, have cascading permissions that can be combined to permission sets and those are assigned to groups or individuals.

Most of our stored procedures calls **perform auth.has_permissions(\_user_id, '[permission full code, for example, orders.cancel_order', \_tenant_id \\\\ 1)**. This way function call is blocked right after user with insufficient privileges tries to call it.


## Database event codes

### Common

| Event code | Description       |
|------------|-------------------|
| 50003      | Permission denied |

### Security

| Event code | Description                            |
|------------|----------------------------------------|
| 50001      | Tenant created                         |
| 50002      | Tenant updated                         |
| 50003      | Tenant deleted                         |
| 50004      | Assign tenant owner                    |
| 50005      | Get tenant users                       |
| 50006      | Get tenant groups                      |
| 50011      | Provider created                       |
| 50012      | Provider updated                       |
| 50013      | Provider deleted                       |
| 50014      | Provider enabled                       |
| 50015      | Provider disabled                      |
| 50016      | Get provider users                     |
| 50101      | User created                           |
| 50102      | User updated                           |
| 50103      | User deleted                           |
| 50104      | User enabled                           |
| 50105      | User disabled                          |
| 50106      | User unlocked                          |
| 50107      | User locked                            |
| 50108      | User identity enabled                  |
| 50109      | User identity disabled                 |
| 50131      | User added to group                    |
| 50133      | User deleted from group                |
| 50134      | User identity created                  |
| 50135      | User identity deleted                  |
| 50136      | User password changed                  |
| 50201      | Group created                          |
| 50202      | Group updated                          |
| 50203      | Group deleted                          |
| 50204      | Group enabled                          |
| 50205      | Group disabled                         |
| 50206      | Group unlocked                         |
| 50207      | Group locked                           |
| 50208      | Group set as external group            |
| 50209      | Group set as hybrid group              |
| 50210      | User requested group members list      |
| 50211      | User requested user group info         |
| 50231      | Group mapping created                  |
| 50233      | Group mapping deleted                  |
| 50301      | Permission set created                 |
| 50302      | Permission set updated                 |
| 50303      | Permission set deleted                 |
| 50304      | Permission assigned                    |
| 50305      | Permission unassigned                  |
| 50306      | Permission assignability changed       |
| 50311      | Permissions added to perm set          |
| 50313      | Permissions removed from perm set      |
| 50331      | Permission created                     |
| 50401      | Token created                          |
| 50402      | Token validated                        |
| 50403      | Token set as used                      |
| 50501      | API key created                        |
| 50502      | API key updated                        |
| 50503      | API key deleted                        |
| 50504      | API key perm set/permission assigned   |
| 50505      | API key perm set/permission unassigned |
| 50506      | API key secret updated                 |

### Security Error codes

| Event code | Description                                                                           |
|------------|---------------------------------------------------------------------------------------|
| 52101      | Cannot ensure user for email provider                                                 |
| 52102      | User cannot register user because the identity is already in use                      |
| 52103      | User does not exist                                                                   |
| 52104      | User is a system user                                                                 |
| 52105      | User is not active                                                                    |
| 52106      | User is locked                                                                        |
| 52107      | Provider is not active                                                                |
| 52108      | User has no access to tenant                                                          |
| 52109      | User has no correct permission in tenant                                              |
| 52110      | User provider identity is not active                                                  |
| 52111      | User provider identity does not exist                                                 |
| 52112      | User is not supposed to log in                                                        |
| 52171      | User group not found                                                                  |
| 52172      | User cannot be added to group because the group is not active                         |
| 52173      | User cannot be added to group because it's either not assignable or an external group |
| 52174      | Either mapped object id or role must not be empty                                     |
| 52175      | Permission set is not assignable                                                      |
| 52176      | Permission is not assignable                                                          |
| 52177      | Permission set is not defined in tenant                                               |
| 52178      | Some permission is not assignable                                                     |
| 52179      | Parent permission does not exist                                                      |
| 52271      | User group cannot be deleted because it's a system group                              |
| 52272      | Either user group id or target user id has to be not null                             |
| 52273      | Either permission set code or permission code has to be not null                      |
| 52274      | Either permission id or code has to be not null                                       |
| 52275      | Permission does not exist                                                             |
| 52276      | The same token is already used                                                        |
| 52277      | Token does not exist                                                                  |
| 52278      | Token is not valid or has expired                                                     |
| 52279      | Token was created for different user                                                  |
| 52280      | User is not tenant owner                                                              |
| 52281      | User is not tenant or group owner                                                     |
| 52281      | User is not tenant or group owner                                                     |


