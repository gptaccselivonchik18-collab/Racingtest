"""Validate a physical-device IPA without implying that it is installable unsigned."""
import plistlib
import struct
import sys
import zipfile

path = sys.argv[1]
with zipfile.ZipFile(path) as archive:
    assert archive.testzip() is None, "Corrupt ZIP"
    prefix = "Payload/VolleyballSimulator.app/"
    info = plistlib.loads(archive.read(prefix + "Info.plist"))
    executable = prefix + info["CFBundleExecutable"]
    data = archive.read(executable)
    assert len(data) > 1_000_000, "Missing or truncated executable"
    assert data[:4] == b"\xcf\xfa\xed\xfe", "Expected little-endian 64-bit Mach-O"
    assert struct.unpack_from("<I", data, 4)[0] == 0x0100000C, "Expected arm64"
    assert info["CFBundleIdentifier"] == "org.volleylab.simulator"
    assert "iPhoneOS" in info["CFBundleSupportedPlatforms"], "Simulator build rejected"
    assert info.get("CADisableMinimumFrameDurationOnPhone") is True, "Missing ProMotion support"
    assert info.get("NSLocalNetworkUsageDescription"), "Missing iOS LAN permission description"
    assert info["CFBundleShortVersionString"] == "0.42.0"
    assert info["CFBundleVersion"] == "42"
    assert "UISupportedInterfaceOrientations" in info, "Missing orientation declarations"
    for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
        if key in info:
            assert {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"} <= set(info[key]), "Both landscape orientations must be supported"
    assert any(name.endswith(".pck") for name in archive.namelist()), "Godot game pack missing"
    if "Unsigned" in path:
        assert not any("_CodeSignature/" in n for n in archive.namelist())
        assert prefix + "embedded.mobileprovision" not in archive.namelist()
print(f"Verified physical-device arm64 IPA: {path}")
