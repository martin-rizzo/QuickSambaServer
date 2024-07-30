# QuickSambaServer Configuration Documentation

This document describes the configuration options for QuickSambaServer.

## Configuration Variables

### RESOURCE
- **Type**: String
- **Format**: `RESOURCE= name | directory | description`
- **Description**: Defines the resources (shared folders) available on the Samba server.
  - `name`: The name of the resource as it will appear to users.
  - `directory`: The local directory path where the resource is located.
  - `description`: A brief explanation of the resource (enclosed in quotes).

Resources are shared as read-only by default. You can use prefixes to modify this behavior:
- `w:` - (read & write) The resource is shared with read and write permissions.
- `-` - (invisible) The resource is hidden from all users but can be assigned to specific users in the user configuration.

**Examples**:
```
RESOURCE= FreeAccess    | ./FreeAccess  | "Accessible to everyone without a password"
RESOURCE= w:Repository  | ./Repository  | "Centralized repository for file sharing and collaboration"
RESOURCE= -AliceHome    | ./alice_files | "This resource contains files exclusive to Alice"
```

### USER
- **Type**: String
- **Format**: `USER= username | password | resources`
- **Description**: Defines users and their access to resources.
  - `username`: The name of the user.
  - `password`: The user's password.
  - `resources`: A list of resources accessible by the user (must match names defined in RESOURCE).

You can use prefixes to modify resource access for each user:
- `w:` - (read & write) The user has read and write access to the resource.
- `--` - (remove) The resource is explicitly removed from the user's access.

**Examples**:
```
USER= alice | alice | w:AliceHome w:FreeAccess -Documentation
USER= bob   | bob   | w:Documentation w:FreeAccess ROMs
USER= carol | carol | w:FreeAccess
```

### SERVER_NAME
- **Type**: String
- **Description**: Sets the name of the Samba server on the network.

**Example**:
```
SERVER_NAME= myserver.local
```

### AVAHI
- **Type**: Boolean
- **Default**: NO
- **Description**: Enables or disables the Avahi service for network discovery.

**Example**:
```
AVAHI= YES
```

### NETBIOS
- **Type**: Boolean
- **Default**: YES
- **Description**: Enables or disables the NetBIOS service for network browsing.

**Example**:
```
NETBIOS= NO
```

### USER_ID
- **Type**: Integer
- **Description**: Sets the user ID used by the Samba server when logged-in users write and access shared files.
- **Note**: This value is ignored if the USER_ID environment variable is set when launching the Docker container.

**Example**:
```
USER_ID=1002
```

### GROUP_ID
- **Type**: Integer
- **Description**: Sets the group ID used by the Samba server when logged-in users write and access shared files.
- **Note**: This value is ignored if the GROUP_ID environment variable is set when launching the Docker container.

**Example**:
```
GROUP_ID=1002
```

## Notes
- Boolean variables can be set to YES/NO (preferred) or TRUE/FALSE.
- Environment variables set when launching the Docker container (e.g., `-e USER_ID=<userid> -e GROUP_ID=<groupid>`) will override the corresponding values in this configuration file.
