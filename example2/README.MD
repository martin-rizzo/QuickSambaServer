# QuickSambaServer Example 2

## Overview

This example ensures that users Alice and Bob have access to their respective home directories as well as the shared documentation directory.

Alice can access the 'AliceHome' resource, which is located in the './alice_files' directory and contains files exclusive to her. Additionally, Alice has access to the 'Documentation' resource located in the './doc_files' directory, where generic Samba documentation files are stored.

Similarly, Bob has access to his exclusive resource 'BobHome' stored in the './bob_files' directory, and he shares access to the 'Documentation' resource with Alice.


## Configuration file (samba.config)

### Available resources
This section details the available resources on the server, along with their respective directories and descriptions.

```bash
#         resource      | directory     | description
RESOURCE= AliceHome     | ./alice_files | "This resource contains files exclusive to Alice"
RESOURCE= BobHome       | ./bob_files   | "This resource contains files exclusive to Bob"
RESOURCE= Documentation | ./doc_files   | "Samba documentation files"
```

### Authorized users
This section outlines the users authorized to access the server and the resources they can access.

```bash
#     user  | password | resources
USER= alice | alice    | AliceHome,Documentation
USER= bob   | bob      | BobHome,Documentation
```
