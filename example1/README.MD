# QuickSambaServer Example 1

## Overview

This example demonstrates the default configuration of QuickSambaServer. QuickSambaServer is set up to allow guest access with no password to the "Files" resource, which is stored in the directory `./samba-data`.

## Configuration

When no configuration file is present, QuickSambaServer defaults to the following settings:

```bash
#         resource  | directory    | description
RESOURCE= Files     | ./samba-data | "This resource contains files available to all users"

#     user  | password | resources
USER= guest |          | Files
```
