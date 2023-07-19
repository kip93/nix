source ../common.sh

requireEnvironment () {
  requireSandboxSupport
  [[ $busybox =~ busybox ]] || skipTest "no busybox"
  if [[ $(uname) != Linux ]]; then skipTest "Need Linux for overlayfs"; fi
  needLocalStore "The test uses --store always so we would just be bypassing the daemon"
}

setupConfig () {
  echo "require-drop-supplementary-groups = false" >> "$NIX_CONF_DIR"/nix.conf
  echo "build-users-group = " >> "$NIX_CONF_DIR"/nix.conf
}

storeDirs () {
  storesRoot="$TEST_ROOT/stores"
  mkdir -p "$storesRoot"
  mount -t tmpfs tmpfs "$storesRoot"
  storeA="$storesRoot/store-a"
  storeBTop="$storesRoot/store-b"
  storeB="local-overlay?root=$storesRoot/merged-store&lower-store=$storeA&upper-layer=$storeBTop"
  # Creating testing directories
  mkdir -p "$storesRoot"/{store-a/nix/store,store-b,merged-store/nix/store,workdir}
}

# Mounting Overlay Store
mountOverlayfs () {
  mergedStorePath="$storesRoot/merged-store/nix/store"
  mount -t overlay overlay \
    -o lowerdir="$storeA/nix/store" \
    -o upperdir="$storeBTop" \
    -o workdir="$storesRoot/workdir" \
    "$mergedStorePath" \
    || skipTest "overlayfs is not supported"

  cleanupOverlay () {
    umount "$storesRoot/merged-store/nix/store"
    rm -r $storesRoot/workdir
  }
  trap cleanupOverlay EXIT
}

remountOverlayfs () {
  mount -o remount "$mergedStorePath"
}

toRealPath () {
  storeDir=$1; shift
  storePath=$1; shift
  echo $storeDir$(echo $storePath | sed "s^$NIX_STORE_DIR^^")
}

initLowerStore () {
  # Init lower store with some stuff
  nix-store --store "$storeA" --add ../dummy

  # Build something in lower store
  drvPath=$(nix-instantiate --store $storeA ../hermetic.nix --arg busybox "$busybox" --arg seed 1)
  path=$(nix-store --store "$storeA" --realise $drvPath)
}

execUnshare () {
  exec unshare --mount --map-root-user "$SHELL" "$@"
}

addTextToStore() {
  storeDir=$1; shift
  filename=$1; shift
  content=$1; shift
  filePath="$TEST_HOME/$filename"
  echo "$content" > "$filePath"
  nix-store --store "$storeDir" --add "$filePath"
}
