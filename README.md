# MAFX SHARE — Android

Native Android file-transfer project (Kotlin, Android Gradle Plugin).

## Current implementation
- English UI with green, white, and blue styling.
- Choose multiple files using Android's system file picker.
- Send files over an existing local Wi-Fi/hotspot network using TCP.
- Receive files on port 45872.
- SHA-256 verification before finalizing received files.
- Partial-file storage to support retry/resume when the same file is sent again.
- GitHub Actions workflow builds a debug APK and stores it as an artifact.

## Important limitations of this first build
- This build transfers over a shared local network. It does not yet implement automatic Wi-Fi Direct discovery, automatic hotspot creation, or remote internet/cloud transfer.
- The receiver screen must remain open while receiving.
- The receiving phone saves files inside the app-specific `Android/data/com.mafx.share/files/Received` directory. A later version should add a user-selectable public destination.
- Resume currently depends on the sender selecting the same source file again and the partial file still existing. The sender hashes the source file before transfer, and the receiver verifies the complete file.
- The transfer protocol is intended for trusted devices on a private network. Do not expose port 45872 to public networks.
- The exact APK has not been compiled in this environment. Use GitHub Actions to compile and review the build result before installing.

## Build APK
Push the repository to GitHub. Open **Actions**, select **Build MAFX SHARE APK**, and run it or push a commit. When the workflow succeeds, open the workflow run and download the `MAFX-SHARE-debug-apk` artifact.

## Transfer test
1. Install the debug APK on two Android phones.
2. Connect both phones to the same Wi-Fi or connect the sender to the receiver's hotspot.
3. On the receiving phone, open MAFX SHARE and tap **RECEIVE FILES**.
4. Find the receiver's local IP address shown in the app.
5. On the sender, enter that IP and tap **SELECT FILES & SEND**.
6. Select files and keep both phones awake and the receiver screen open during the transfer.

The first transfer may be limited by the phones, network conditions, and hotspot configuration. This project does not claim a fixed 10 GB transfer time.
