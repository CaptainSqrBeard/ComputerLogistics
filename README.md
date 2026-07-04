# Computer Logistics
This is collection of logistics programs for CC:Tweaked.

## Features
- Logistics storage server
- Storage manager
- Basic cryptography: Signing network messages to prevent spoofing.
- - This doesn't prevent from listening these messages by anyone else
- - Also this doesn't prevent direct storage peripheral manipulation in local network

## Modules
You need to manually add modules from `modules` to program folder. See programs section to see what modules each program require.

Also you need to install [CCryptoLib](https://github.com/migeyel/ccryptolib/releases) on computer. Run installer and put `ccryptolib` in program folder.

## Programs
### logisticsMainStorage
Logistics server for storage management. Processes requests to move items between main storage and other containers in the network.

#### Required modules
- [CCryptoLib](https://github.com/migeyel/ccryptolib/releases)
- csecureNet
- cstorage

### example
An example program which purpose is show how to work with storage server and modules

#### Required modules
- [CCryptoLib](https://github.com/migeyel/ccryptolib/releases)
- csecureNet
- logisticsHelper

### legacyStorageManager
*Co-author: [5w14](https://github.com/5w14)*

Legacy program that gives manual access to main storage through simple GUI. It can:
- Search items in the storage
- Get items from the storage
- Put items inside the storage

Use `cli.lua` to configure it.

This program was not built with other logistic programs in mind. It's completely standalone. All required modules come pre-installed in program folder.
