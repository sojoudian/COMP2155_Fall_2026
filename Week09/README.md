# Week 09: Run a Router with crouter

`crouter` runs a router on your computer. You do not need PNETLab, GNS3, or EVE-NG.

| File | Computer |
|---|---|
| `crouter-darwin-arm64` | macOS on Apple Silicon (M chip) |
| `crouter-windows-amd64.exe` | Windows on x86-64 |

`r1-lan.cfg` is the configuration of R1.

## Download the configuration

Open a terminal in the folder `Week09`, and run this command:

```
curl -O https://raw.githubusercontent.com/sojoudian/COMP2155_Fall_2026/master/Week09/r1-lan.cfg
```

## Run the router

Open a terminal in the folder `Week09`, and run the command for your computer.

macOS:

```
chmod +x crouter-darwin-arm64
xattr -d com.apple.quarantine crouter-darwin-arm64
./crouter-darwin-arm64 --config r1-lan.cfg
```

Windows:

```
.\crouter-windows-amd64.exe --config r1-lan.cfg
```
