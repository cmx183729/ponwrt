#!/usr/bin/env bash
# Scoped external-package hook for the Nokia/Bell XG-040G-MD image.
#
# It deliberately never edits feeds.conf.default, PON drivers, BOSA/RI data,
# DTS files, or board network definitions.  It materializes only the selected
# upper-layer packages under package/xg040-feeds after standard feeds are ready.

set -euo pipefail

TOPDIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
EXTERNAL_DIR="$TOPDIR/package/xg040-feeds"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/xg040g-md-feeds.XXXXXX")"
# All external inputs are fixed to reviewed commits.  Update a ref and its
# commit deliberately when an upstream package changes.
AIROHA_NPU_REF="main"
AIROHA_NPU_COMMIT="14521b8414da1e98517a295d8ec267087c7dde8e"
OPENCLASH_REF="dev"
OPENCLASH_COMMIT="e43de375fdf4fd69ce0fa2416462819747dcc2e9"
MOSDNS_REF="v5"
MOSDNS_COMMIT="bd40245303cd0ba56804d49eed5dbc4be2a082ca"
GEODATA_REF="master"
GEODATA_COMMIT="2e3845caae172326f02b3406048c7a3613f3dee5"
ISTORE_REF="main"
ISTORE_COMMIT="a97ace34f2da358a015b094d326bba2697697f2e"
MIHOMO_REF="main"
MIHOMO_COMMIT="7b203f6c4c5e94c6c0026acb301090aa1d310e7f"

cleanup() {
	rm -rf -- "$WORKDIR"
}
trap cleanup EXIT INT TERM

die() {
	echo "xg040g-md-feeds: $*" >&2
	exit 1
}

require_file() {
	[ -f "$1" ] || die "required file is missing: $1"
}

assert_pon_baseline() {
	local protected
	for protected in \
		"target/linux/airoha/an7581/base-files/etc/board.d/02_network" \
		"target/linux/airoha/an7581/base-files/lib/upgrade/platform.sh" \
		"target/linux/airoha/base-files/etc/board.d/03_pon_data" \
		"target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi" \
		"target/linux/airoha/dts/an758x-nokia_xg-040g-ubi-parts.dtsi" \
		"target/linux/airoha/image/an7581.mk"; do
		require_file "$TOPDIR/$protected"
	done

	# Do not silently run this package hook on top of local changes to protected
	# optical/network definitions.  A clean checkout passes this test.
	git -C "$TOPDIR" diff --quiet -- \
		target/linux/airoha/an7581/base-files/etc/board.d/02_network \
		target/linux/airoha/an7581/base-files/lib/upgrade/platform.sh \
		target/linux/airoha/base-files/etc/board.d/03_pon_data \
		target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi \
		target/linux/airoha/dts/an758x-nokia_xg-040g-ubi-parts.dtsi \
		target/linux/airoha/image/an7581.mk || \
		die "protected PON/DTS/network files have local changes; resolve them before building"
}

reset_external_dir() {
	[ "$EXTERNAL_DIR" = "$TOPDIR/package/xg040-feeds" ] || die "unsafe external package path: $EXTERNAL_DIR"
	rm -rf -- "$EXTERNAL_DIR"
	mkdir -p "$EXTERNAL_DIR"
}

clone_repo() {
	local name="$1" url="$2" ref="$3" expected_commit="$4"
	local destination="$WORKDIR/$name"
	local actual_commit

	mkdir -p "$destination"
	git -C "$destination" init -q
	git -C "$destination" remote add origin "$url"
	git -C "$destination" fetch --depth 1 origin "$expected_commit"
	git -C "$destination" checkout --detach -q FETCH_HEAD
	actual_commit="$(git -C "$destination" rev-parse HEAD)"
	[ "$actual_commit" = "$expected_commit" ] || die "${name} did not resolve to pinned commit ${expected_commit}"
	printf 'source %-18s %-8s %s\n' "$name" "$ref" "$actual_commit"
}

remove_feed_symlink() {
	local package_name="$1" candidate
	for candidate in "$TOPDIR"/package/feeds/*/"$package_name"; do
		[ -e "$candidate" ] || [ -L "$candidate" ] || continue
		[ -L "$candidate" ] || die "refusing to replace non-symlink package path: $candidate"
		rm -- "$candidate"
	done
}

copy_package_tree() {
	local source_root="$1" relative_path="$2" package_name="$3"
	local source_dir="$source_root/$relative_path"
	local destination="$EXTERNAL_DIR/$package_name"

	require_file "$source_dir/Makefile"
	mkdir -p "$destination"
	(
		cd "$source_dir"
		tar --exclude-vcs -cf - .
	) | (
		cd "$destination"
		tar -xf -
	)
}

assert_full_npu_controls() {
	local npu_dir="$EXTERNAL_DIR/luci-app-airoha-npu"
	local rpc="$npu_dir/root/usr/libexec/rpcd/luci.airoha_npu"
	local acl="$npu_dir/root/usr/share/rpcd/acl.d/luci-app-airoha-npu.json"
	local ui="$npu_dir/htdocs/luci-static/resources/view/airoha_npu/status.js"
	local method handler

	require_file "$rpc"
	require_file "$acl"
	require_file "$ui"

	# The source is pinned, but keep a positive contract here so a future source
	# refresh cannot silently drop the original governor/frequency/PLL controls.
	for method in setGovernor setMaxFreq setOverclock; do
		grep -Fq -- "method: '$method'" "$ui" || die "NPU LuCI control is missing: $method"
		grep -Fq -- "\"$method\"" "$rpc" || die "NPU RPC control is missing: $method"
		grep -Fq -- "\"$method\"" "$acl" || die "NPU ACL control is missing: $method"
	done
	grep -Eq '"write"[[:space:]]*:' "$acl" || die "NPU ACL does not grant write access"
	for handler in set_governor set_max_freq set_overclock configure_armpll; do
		grep -Fq -- "$handler()" "$rpc" || die "NPU backend is missing: $handler"
	done
	grep -Fq -- 'devmem $CR_CPUPLL_SDM_PCW 32' "$rpc" || die "NPU PLL write path is missing"
	grep -Fq -- 'function renderOcControls' "$ui" || die "NPU overclock panel is missing"
}

main() {
	assert_pon_baseline
	reset_external_dir

	# The declared branch labels are for auditing; immutable commits are fetched.
	# The NPU package is copied unchanged so its original LuCI CPU/PLL controls
	# (governor, maximum frequency and overclock) remain available.
	clone_repo airoha-npu https://github.com/rchen14b/luci-app-airoha-npu.git "$AIROHA_NPU_REF" "$AIROHA_NPU_COMMIT"
	clone_repo openclash https://github.com/vernesong/OpenClash.git "$OPENCLASH_REF" "$OPENCLASH_COMMIT"
	clone_repo mosdns https://github.com/sbwml/luci-app-mosdns.git "$MOSDNS_REF" "$MOSDNS_COMMIT"
	clone_repo geodata https://github.com/sbwml/v2ray-geodata.git "$GEODATA_REF" "$GEODATA_COMMIT"
	clone_repo istore https://github.com/linkease/istore.git "$ISTORE_REF" "$ISTORE_COMMIT"
	clone_repo mihomo https://github.com/nikkinikki-org/OpenWrt-nikki.git "$MIHOMO_REF" "$MIHOMO_COMMIT"

	# Replace only links created by scripts/feeds.  Never remove feed source trees.
	local package_name
	for package_name in \
		luci-app-airoha-npu luci-app-openclash mosdns luci-app-mosdns geo2txt \
		v2ray-geodata luci-app-store luci-lib-taskd luci-lib-xterm taskd mihomo-meta; do
		remove_feed_symlink "$package_name"
	done

	copy_package_tree "$WORKDIR/airoha-npu" . luci-app-airoha-npu
	assert_full_npu_controls
	copy_package_tree "$WORKDIR/openclash" luci-app-openclash luci-app-openclash
	copy_package_tree "$WORKDIR/mosdns" mosdns mosdns
	copy_package_tree "$WORKDIR/mosdns" luci-app-mosdns luci-app-mosdns
	copy_package_tree "$WORKDIR/mosdns" geo2txt geo2txt
	copy_package_tree "$WORKDIR/geodata" . v2ray-geodata
	copy_package_tree "$WORKDIR/istore" luci/luci-app-store luci-app-store
	copy_package_tree "$WORKDIR/istore" luci/luci-lib-taskd luci-lib-taskd
	copy_package_tree "$WORKDIR/istore" luci/luci-lib-xterm luci-lib-xterm
	copy_package_tree "$WORKDIR/istore" luci/taskd taskd
	copy_package_tree "$WORKDIR/mihomo" mihomo-meta mihomo-meta

	echo "xg040g-md-feeds: selected external packages are ready in $EXTERNAL_DIR"
}

main "$@"
