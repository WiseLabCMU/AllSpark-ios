# Changelog

## [0.5.1](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.5.0...v0.5.1) (2026-04-21)


### Bug Fixes

* corrected simulation video output dimensions ([d6dc64e](https://github.com/WiseLabCMU/AllSpark-ios/commit/d6dc64ed7c8a2dc2153431b04384a7a5e944df2b))

## [0.5.0](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.4.0...v0.5.0) (2026-04-21)


### Features

* add connection button/state on all views ([4d891d5](https://github.com/WiseLabCMU/AllSpark-ios/commit/4d891d50029a18e77cd5d37ff65542a5271b8592))
* add status info consolidating state data off the settings config ([3bd181d](https://github.com/WiseLabCMU/AllSpark-ios/commit/3bd181d33fab7d450530757d7c6d13c7e18afaa4))
* Anti-jitter metadata logging, ms-scale chunk naming, & UI modality overlay ([6e0d9a9](https://github.com/WiseLabCMU/AllSpark-ios/commit/6e0d9a9006c15114b336a81cec87d14edaceadf6))
* Gate Bluetooth Core behind server comms policy and rm Info.plist requirement ([4d9bb3e](https://github.com/WiseLabCMU/AllSpark-ios/commit/4d9bb3ed1f39436ec2a35ae9600670b0a7bbd6a1))
* Persistent client connection nonces and txt log sync capabilities ([5dac552](https://github.com/WiseLabCMU/AllSpark-ios/commit/5dac5528cf3be35335758648975c276c924aae38))
* **privacy:** add blur for full person; add demo video in sim ([5ed196d](https://github.com/WiseLabCMU/AllSpark-ios/commit/5ed196d531adaf42fdac31d041d0986a76e58bdf))
* **privacy:** add pose estimation as an optional privacy filter ([7d05b1f](https://github.com/WiseLabCMU/AllSpark-ios/commit/7d05b1f274ea6e0d892835c37b9e25bfde903814))


### Bug Fixes

* consolidate magic numbers ([aa62688](https://github.com/WiseLabCMU/AllSpark-ios/commit/aa626887d8a962aff32b98273a7cde19c107c87b))
* Correct malformed icon glob in gitignore ([7967395](https://github.com/WiseLabCMU/AllSpark-ios/commit/79673952b034325d73db9d6d497796a523a2673c))
* Guard serverTrust optional and add post-beta pinning comment ([eef6d15](https://github.com/WiseLabCMU/AllSpark-ios/commit/eef6d1551417dd042dd5c05a89640075a33ab463))
* prefer pixelation over gaussian blur ([699d901](https://github.com/WiseLabCMU/AllSpark-ios/commit/699d901a12c38dd7c650cc0d6fa2d37922534e28))
* remove interfaces from discovered services ([e83f67b](https://github.com/WiseLabCMU/AllSpark-ios/commit/e83f67bcbc2c0f03e94df275b6e4c318908300ed))
* Remove no-op Re-check button and add beta tab-order comment ([433132e](https://github.com/WiseLabCMU/AllSpark-ios/commit/433132eb6ad702b01533628843d2323b43fa8559))
* Replace deprecated presentationMode and unblock stopScanning from main thread ([3db9d4c](https://github.com/WiseLabCMU/AllSpark-ios/commit/3db9d4c001ddd3a85fc16832963bfc89f9fb8305))
* Reset isBluetoothOn when bluetoothManager is destroyed by policy ([55c7ece](https://github.com/WiseLabCMU/AllSpark-ios/commit/55c7ece154e672c920332dfed0c300b3cdcf877f))
* Show Bluetooth as Not Monitored when policy has not activated it ([aa9937d](https://github.com/WiseLabCMU/AllSpark-ios/commit/aa9937d0e1100e8f6646d864eddf918504675f73))
* Thread-safe timestamp read, pixelBufferPool reuse, and stale comment ([29ce4f4](https://github.com/WiseLabCMU/AllSpark-ios/commit/29ce4f413f161089f23ba10493d93a5a1dd5045d))
* update release please to latest ([e9cc2ad](https://github.com/WiseLabCMU/AllSpark-ios/commit/e9cc2add1ba7a9a946b5175342d57167d9259587))
* URLSession leak, force-unwrap crash, nonce collision logic, and orphaned txt cleanup ([9e57f04](https://github.com/WiseLabCMU/AllSpark-ios/commit/9e57f04056e1d1da9192f4be27f90eb4a07746e0))

## [0.4.0](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.3.0...v0.4.0) (2026-03-10)


### Features

* **comms:** add communications policy to define which channels should be allowed ([5dc4f94](https://github.com/WiseLabCMU/AllSpark-ios/commit/5dc4f94482060adfb7885628a5cc4af838820a3e))


### Bug Fixes

* correct several deprecated api calls ([2760f0c](https://github.com/WiseLabCMU/AllSpark-ios/commit/2760f0c6a64699ef27e246278bd1c707082d4901))
* fix pairing view camera orientation ([e52152b](https://github.com/WiseLabCMU/AllSpark-ios/commit/e52152bc44edeee006061e73dce67dabe272277f))
* repair failed autoconnect after qr code scan ([9ea4c8d](https://github.com/WiseLabCMU/AllSpark-ios/commit/9ea4c8dbae374a546ce16f88e34b0b672a217da1))

## [0.3.0](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.2.0...v0.3.0) (2026-02-20)


### Features

* **bonjour:** add .local allspark server discovery ([741eff1](https://github.com/WiseLabCMU/AllSpark-ios/commit/741eff1a25afa5ab89a5a5b9df96693c372e2daa))
* **camera:** added auto record of video chunks and remote recall ([351337a](https://github.com/WiseLabCMU/AllSpark-ios/commit/351337a8ad0688a2258d605fa4d739c0e1983aa3))
* **client:** add list of device interfaces for debug ([500c213](https://github.com/WiseLabCMU/AllSpark-ios/commit/500c2134a96e5921919fd59021102f14744bf96c))
* **network:** manage network connection as a background task ([e36b643](https://github.com/WiseLabCMU/AllSpark-ios/commit/e36b6434656666bc949e48b9ca79a418599987a4))
* **server:** add qrcode scan for alternate out of band setup ([9db96f7](https://github.com/WiseLabCMU/AllSpark-ios/commit/9db96f7674ec0f585e7ec57566caaa516ddb2110))
* **server:** added python implementation of server ([7286f69](https://github.com/WiseLabCMU/AllSpark-ios/commit/7286f695606a88cd9c08960582888d32d002e847))
* **server:** make general client settings config at server level ([2611223](https://github.com/WiseLabCMU/AllSpark-ios/commit/261122306d28c948c97bd4830dfb9d3b461b7b32))
* **video:** add video storage limit monitor ([531f1bd](https://github.com/WiseLabCMU/AllSpark-ios/commit/531f1bd766e7deef82617c1db6c85d54b3517ee9))
* **ws:** migrate connection status to inline settings ([a8cf255](https://github.com/WiseLabCMU/AllSpark-ios/commit/a8cf2555d1de9afab61ebd87caba0404f86f4919))


### Bug Fixes

* **config:** perform deep merge from default config ([339ca0c](https://github.com/WiseLabCMU/AllSpark-ios/commit/339ca0c98894ab7362fe113dd988ee16ee5cc7e5))
* **flip:** ensure camera flip switches video chunks ([9b0974b](https://github.com/WiseLabCMU/AllSpark-ios/commit/9b0974b8dde1001e348b041c26fc5430e2185e9d))
* **server:** keep only one set of default settings ([6c1248a](https://github.com/WiseLabCMU/AllSpark-ios/commit/6c1248a52b133a9cfa77d378429ae6ded4305555))
* **video:** handle multiple file uploads asynchronously ([1a7a09d](https://github.com/WiseLabCMU/AllSpark-ios/commit/1a7a09d842d904736a5c48967e03ba74bf44b3a1))

## [0.2.0](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.1.0...v0.2.0) (2026-01-23)


### Features

* adding video file save of blurred video ([6889772](https://github.com/WiseLabCMU/AllSpark-ios/commit/688977254ef536bd6a9122d59a3fb1c52cf3992a))
* **audio:** add audio recording to video file capture ([7f10ff2](https://github.com/WiseLabCMU/AllSpark-ios/commit/7f10ff2a1d9b9561f9995c5c78d993d946135298))
* **ws:** allow camera view to control ws connect/disconnect ([cc722d4](https://github.com/WiseLabCMU/AllSpark-ios/commit/cc722d41ca3022ed8b8fbcb51b90574d09db55a1))


### Bug Fixes

* **upload:** convert file upload and tests to websockets ([740d132](https://github.com/WiseLabCMU/AllSpark-ios/commit/740d132fe8e7ba03cf56fc8277b4ece95abe7753))

## [0.1.0](https://github.com/WiseLabCMU/AllSpark-ios/compare/v0.0.1...v0.1.0) (2025-12-03)


### Features

* added privacy filter ([682841a](https://github.com/WiseLabCMU/AllSpark-ios/commit/682841acf0ee0e148f6f8bf1759b6e717f553513))
