/**
 * Incus/LXD container image presets & visual catalog.
 * Instead of forcing the operator to type "ubuntu:24.04", the container
 * form offers a rich visual catalog of distributions and friendly labels
 * backed by valid Incus/LXD image references and local cached images.
 */

import { t } from '$lib/i18n.svelte.js';

export const INCUS_IMAGE_CATEGORIES = [
  {
    id: 'all',
    get label() {
      return t('imageCatalog.catAll');
    },
  },
  {
    id: 'local',
    get label() {
      return t('imageCatalog.catLocal');
    },
  },
  {
    id: 'images',
    get label() {
      return t('imageCatalog.catImages');
    },
  },
  {
    id: 'popular',
    get label() {
      return t('imageCatalog.catPopular');
    },
  },
  {
    id: 'minimal',
    get label() {
      return t('imageCatalog.catMinimal');
    },
  },
  {
    id: 'enterprise',
    get label() {
      return t('imageCatalog.catEnterprise');
    },
  },
  {
    id: 'dev',
    get label() {
      return t('imageCatalog.catDev');
    },
  },
];

export const INCUS_IMAGE_PRESETS = [
  // Populares / Servidor
  {
    label: 'Ubuntu 26.04 (Resolute)',
    ref: 'images:ubuntu/resolute',
    category: 'popular',
    distro: 'ubuntu',
    get desc() {
      return t('imageCatalog.descUbuntu2604');
    },
    arch: 'x86_64 / arm64',
    badge: '26.04',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-orange-500/20 to-orange-600/10 border-orange-500/30 text-orange-400',
  },
  {
    // NOTE: intentionally "images:ubuntu/24.04", NOT the legacy
    // "ubuntu:24.04" (cloud-images.ubuntu.com) remote. The backend's
    // Incus client doesn't recognize that stream's image metadata
    // format, so pulling it always fails with "Alias ... doesn't
    // exist" — images.linuxcontainers.org mirrors the same release and
    // actually works.
    label: 'Ubuntu 24.04 LTS (Noble)',
    ref: 'images:ubuntu/24.04',
    category: 'popular',
    distro: 'ubuntu',
    get desc() {
      return t('imageCatalog.descUbuntu2404');
    },
    arch: 'x86_64 / arm64',
    badge: 'LTS',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-orange-500/20 to-orange-600/10 border-orange-500/30 text-orange-400',
  },
  {
    label: 'Ubuntu 22.04 LTS (Jammy)',
    ref: 'images:ubuntu/22.04',
    category: 'popular',
    distro: 'ubuntu',
    get desc() {
      return t('imageCatalog.descUbuntu2204');
    },
    arch: 'x86_64 / arm64',
    badge: 'LTS',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-orange-500/20 to-orange-600/10 border-orange-500/30 text-orange-400',
  },
  {
    label: 'Debian 14 (Forky)',
    ref: 'images:debian/forky',
    category: 'dev',
    distro: 'debian',
    get desc() {
      return t('imageCatalog.descDebian14');
    },
    arch: 'x86_64 / arm64',
    badge: 'Debian 14',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 15,
    color: 'from-rose-500/20 to-rose-600/10 border-rose-500/30 text-rose-400',
  },
  {
    label: 'Debian 13 (Trixie)',
    ref: 'images:debian/13',
    category: 'popular',
    distro: 'debian',
    get desc() {
      return t('imageCatalog.descDebian13');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeTesting');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-rose-500/20 to-rose-600/10 border-rose-500/30 text-rose-400',
  },
  {
    label: 'Debian 12 (Bookworm)',
    ref: 'images:debian/12',
    category: 'popular',
    distro: 'debian',
    get desc() {
      return t('imageCatalog.descDebian12');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeStable');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-rose-500/20 to-rose-600/10 border-rose-500/30 text-rose-400',
  },
  {
    label: 'Debian 11 (Bullseye)',
    ref: 'images:debian/11',
    category: 'popular',
    distro: 'debian',
    get desc() {
      return t('imageCatalog.descDebian11');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeOldstable');
    },
    recommended_vcpu: 1,
    recommended_ram_mb: 1024,
    recommended_disk_gb: 10,
    color: 'from-rose-500/20 to-rose-600/10 border-rose-500/30 text-rose-400',
  },
  {
    label: 'Debian Sid (Unstable)',
    ref: 'images:debian/sid',
    category: 'dev',
    distro: 'debian',
    get desc() {
      return t('imageCatalog.descDebianSid');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeUnstable');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 15,
    color: 'from-rose-500/20 to-rose-600/10 border-rose-500/30 text-rose-400',
  },

  // Ligeras / Minimalistas
  {
    label: 'Alpine Linux 3.24',
    ref: 'images:alpine/3.24',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpine324');
    },
    arch: 'x86_64 / arm64',
    badge: '3.24',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Alpine Linux 3.23',
    ref: 'images:alpine/3.23',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpine323');
    },
    arch: 'x86_64 / arm64',
    badge: '3.23',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Alpine Linux 3.22',
    ref: 'images:alpine/3.22',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpine322');
    },
    arch: 'x86_64 / arm64',
    badge: '3.22',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Alpine Linux 3.21',
    ref: 'images:alpine/3.21',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpine321');
    },
    arch: 'x86_64 / arm64',
    badge: '5 MB',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Alpine Linux 3.20',
    ref: 'images:alpine/3.20',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpine320');
    },
    arch: 'x86_64 / arm64',
    badge: '5 MB',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Alpine Linux Edge',
    ref: 'images:alpine/edge',
    category: 'minimal',
    distro: 'alpine',
    get desc() {
      return t('imageCatalog.descAlpineEdge');
    },
    arch: 'x86_64 / arm64',
    badge: 'Edge',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 5,
    color: 'from-sky-500/20 to-sky-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'Void Linux (glibc)',
    ref: 'images:voidlinux',
    category: 'minimal',
    distro: 'void',
    get desc() {
      return t('imageCatalog.descVoidGlibc');
    },
    arch: 'x86_64',
    get badge() {
      return t('imageCatalog.badgeLightweight');
    },
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 10,
    color: 'from-emerald-500/20 to-emerald-600/10 border-emerald-500/30 text-emerald-400',
  },
  {
    label: 'Void Linux (musl)',
    ref: 'images:voidlinux/musl',
    category: 'minimal',
    distro: 'void',
    get desc() {
      return t('imageCatalog.descVoidMusl');
    },
    arch: 'x86_64',
    badge: 'musl',
    recommended_vcpu: 1,
    recommended_ram_mb: 512,
    recommended_disk_gb: 10,
    color: 'from-emerald-500/20 to-emerald-600/10 border-emerald-500/30 text-emerald-400',
  },
  {
    label: 'OpenWrt 23.05',
    ref: 'images:openwrt/23.05',
    category: 'minimal',
    distro: 'openwrt',
    get desc() {
      return t('imageCatalog.descOpenwrt2305');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeRouter');
    },
    recommended_vcpu: 1,
    recommended_ram_mb: 256,
    recommended_disk_gb: 2,
    color: 'from-teal-500/20 to-cyan-600/10 border-teal-500/30 text-teal-400',
  },
  {
    label: 'Devuan 5 (Daedalus)',
    ref: 'images:devuan/daedalus',
    category: 'minimal',
    distro: 'devuan',
    get desc() {
      return t('imageCatalog.descDevuan5');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeNoSystemd');
    },
    recommended_vcpu: 1,
    recommended_ram_mb: 1024,
    recommended_disk_gb: 10,
    color: 'from-purple-500/20 to-indigo-600/10 border-purple-500/30 text-purple-400',
  },

  // Enterprise / RHEL
  {
    label: 'Rocky Linux 10',
    ref: 'images:rockylinux/10',
    category: 'enterprise',
    distro: 'rocky',
    get desc() {
      return t('imageCatalog.descRocky10');
    },
    arch: 'x86_64 / arm64',
    badge: 'RHEL 10',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-emerald-500/20 to-teal-600/10 border-emerald-500/30 text-emerald-400',
  },
  {
    label: 'Rocky Linux 9 (images:)',
    ref: 'images:rockylinux/9',
    category: 'enterprise',
    distro: 'rocky',
    get desc() {
      return t('imageCatalog.descRocky9');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeEnterprise');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-emerald-500/20 to-teal-600/10 border-emerald-500/30 text-emerald-400',
  },
  {
    label: 'Rocky Linux 8',
    ref: 'images:rockylinux/8',
    category: 'enterprise',
    distro: 'rocky',
    get desc() {
      return t('imageCatalog.descRocky8');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeEnterprise');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-emerald-500/20 to-teal-600/10 border-emerald-500/30 text-emerald-400',
  },
  {
    label: 'AlmaLinux 9 (images:)',
    ref: 'images:almalinux/9',
    category: 'enterprise',
    distro: 'almalinux',
    get desc() {
      return t('imageCatalog.descAlma9');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeEnterprise');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'AlmaLinux 8',
    ref: 'images:almalinux/8',
    category: 'enterprise',
    distro: 'almalinux',
    get desc() {
      return t('imageCatalog.descAlma8');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeEnterprise');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'CentOS Stream 10',
    ref: 'images:centos/10-Stream',
    category: 'enterprise',
    distro: 'centos',
    get desc() {
      return t('imageCatalog.descCentos10');
    },
    arch: 'x86_64 / arm64',
    badge: 'Stream 10',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-purple-500/20 to-purple-600/10 border-purple-500/30 text-purple-400',
  },
  {
    label: 'CentOS Stream 9',
    ref: 'images:centos/9-Stream',
    category: 'enterprise',
    distro: 'centos',
    get desc() {
      return t('imageCatalog.descCentos9');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeUpstream');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-purple-500/20 to-purple-600/10 border-purple-500/30 text-purple-400',
  },
  {
    label: 'Oracle Linux 10',
    ref: 'images:oracle/10',
    category: 'enterprise',
    distro: 'oracle',
    get desc() {
      return t('imageCatalog.descOracle10');
    },
    arch: 'x86_64 / arm64',
    badge: 'Oracle 10',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-red-500/20 to-red-600/10 border-red-500/30 text-red-400',
  },
  {
    label: 'Oracle Linux 9',
    ref: 'images:oracle/9',
    category: 'enterprise',
    distro: 'oracle',
    get desc() {
      return t('imageCatalog.descOracle9');
    },
    arch: 'x86_64',
    badge: 'UEK',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-red-500/20 to-red-600/10 border-red-500/30 text-red-400',
  },
  {
    label: 'Amazon Linux 2023',
    ref: 'images:amazonlinux/2023',
    category: 'enterprise',
    distro: 'amazon',
    get desc() {
      return t('imageCatalog.descAmazon2023');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeCloud');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 15,
    color: 'from-amber-500/20 to-orange-600/10 border-amber-500/30 text-amber-400',
  },
  {
    label: 'openSUSE 16.0',
    ref: 'images:opensuse/16.0',
    category: 'enterprise',
    distro: 'opensuse',
    get desc() {
      return t('imageCatalog.descOpensuse160');
    },
    arch: 'x86_64 / arm64',
    badge: 'Leap 16',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-lime-500/20 to-green-600/10 border-lime-500/30 text-lime-400',
  },
  {
    label: 'openSUSE Leap 15.6',
    ref: 'images:opensuse/15.6',
    category: 'enterprise',
    distro: 'opensuse',
    get desc() {
      return t('imageCatalog.descOpensuse156');
    },
    arch: 'x86_64 / arm64',
    badge: 'Leap',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-lime-500/20 to-green-600/10 border-lime-500/30 text-lime-400',
  },

  // Desarrollo / Rolling
  {
    label: 'Arch Linux',
    ref: 'images:archlinux',
    category: 'dev',
    distro: 'arch',
    get desc() {
      return t('imageCatalog.descArch');
    },
    arch: 'x86_64',
    get badge() {
      return t('imageCatalog.badgeRolling');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-cyan-500/20 to-blue-600/10 border-cyan-500/30 text-cyan-400',
  },
  {
    label: 'Fedora 44 (Rawhide/Next)',
    ref: 'images:fedora/44',
    category: 'dev',
    distro: 'fedora',
    get desc() {
      return t('imageCatalog.descFedora44');
    },
    arch: 'x86_64 / arm64',
    badge: 'Fedora 44',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'Fedora 43',
    ref: 'images:fedora/43',
    category: 'dev',
    distro: 'fedora',
    get desc() {
      return t('imageCatalog.descFedora43');
    },
    arch: 'x86_64 / arm64',
    badge: 'Fedora 43',
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'Fedora 41',
    ref: 'images:fedora/41',
    category: 'dev',
    distro: 'fedora',
    get desc() {
      return t('imageCatalog.descFedora41');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeCuttingEdge');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'Fedora 40',
    ref: 'images:fedora/40',
    category: 'dev',
    distro: 'fedora',
    get desc() {
      return t('imageCatalog.descFedora40');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeStable');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-blue-500/20 to-indigo-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'NixOS 26.05',
    ref: 'images:nixos/26.05',
    category: 'dev',
    distro: 'nixos',
    get desc() {
      return t('imageCatalog.descNixos2605');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeDeclarative');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-sky-500/20 to-blue-600/10 border-sky-500/30 text-sky-400',
  },
  {
    label: 'openSUSE Tumbleweed',
    ref: 'images:opensuse/tumbleweed',
    category: 'dev',
    distro: 'opensuse',
    get desc() {
      return t('imageCatalog.descOpensuseTumbleweed');
    },
    arch: 'x86_64',
    get badge() {
      return t('imageCatalog.badgeRolling');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 2048,
    recommended_disk_gb: 20,
    color: 'from-lime-500/20 to-green-600/10 border-lime-500/30 text-lime-400',
  },
  {
    label: 'Kali Linux',
    ref: 'images:kali',
    category: 'dev',
    distro: 'kali',
    get desc() {
      return t('imageCatalog.descKali');
    },
    arch: 'x86_64',
    get badge() {
      return t('imageCatalog.badgeSecurity');
    },
    recommended_vcpu: 2,
    recommended_ram_mb: 4096,
    recommended_disk_gb: 25,
    color: 'from-blue-600/20 to-cyan-600/10 border-blue-500/30 text-blue-400',
  },
  {
    label: 'Gentoo Linux',
    ref: 'images:gentoo',
    category: 'dev',
    distro: 'gentoo',
    get desc() {
      return t('imageCatalog.descGentoo');
    },
    arch: 'x86_64 / arm64',
    get badge() {
      return t('imageCatalog.badgeSource');
    },
    recommended_vcpu: 4,
    recommended_ram_mb: 4096,
    recommended_disk_gb: 30,
    color: 'from-purple-500/20 to-pink-600/10 border-purple-500/30 text-purple-400',
  },
];

export const CUSTOM_IMAGE = {
  get label() {
    return t('imageCatalog.customImage');
  },
  ref: '',
};

/**
 * Friendly label for an image reference. Known presets map to their
 * distribution name; unknown/custom references fall back to the raw ref.
 */
export function labelForImage(ref, dynamicList = null) {
  if (!ref) return '';
  const list = dynamicList && dynamicList.length ? dynamicList : INCUS_IMAGE_PRESETS;
  const hit = list.find((p) => p.ref === ref);
  return hit ? hit.label : ref;
}

/**
 * Returns recommended resources for a given image reference.
 */
export function getRecommendedResources(ref, dynamicList = null) {
  if (!ref) return { vcpus: 2, ramMB: 2048, diskGB: 20 };
  const list = dynamicList && dynamicList.length ? dynamicList : INCUS_IMAGE_PRESETS;
  const hit = list.find((p) => p.ref === ref);
  if (hit) {
    return {
      vcpus: hit.rec_vcpus || hit.recommended_vcpu || 2,
      ramMB: hit.rec_ram_mb || hit.recommended_ram_mb || 2048,
      diskGB: hit.rec_disk_gb || hit.recommended_disk_gb || 20,
    };
  }
  return { vcpus: 2, ramMB: 2048, diskGB: 20 };
}

/**
 * True when ref is a bare Incus image fingerprint: the hex digest an
 * image is stored under, in full (64 chars) or in the 12-char short
 * form the catalog and `incus image list` show.
 *
 * A locally cached image need not carry any alias — an image pulled by
 * an instance create is stored by fingerprint alone — so the API hands
 * those back with the fingerprint AS their ref. Treating that as
 * malformed rejected a value that came straight out of our own catalog.
 */
export function isImageFingerprint(ref) {
  return /^[0-9a-f]{12}$|^[0-9a-f]{64}$/.test((ref || '').trim().toLowerCase());
}

/**
 * True when ref is something Incus can resolve to an image: either
 * <remote>:<alias>, or a local image fingerprint.
 */
export function isValidImageRef(ref) {
  const value = (ref || '').trim();
  if (!value) return false;
  return value.includes(':') || isImageFingerprint(value);
}

/**
 * Filter images list by category and search query.
 */
export function filterIncusImages(images, { category = 'all', search = '' } = {}) {
  const query = (search || '').trim().toLowerCase();
  let list = images || [];

  if (category === 'local') {
    list = list.filter((img) => img.is_local);
  } else if (category === 'images') {
    list = list.filter((img) => (img.ref || '').startsWith('images:'));
  } else if (category && category !== 'all') {
    list = list.filter((img) => img.category === category);
  }

  if (!query) return list;

  return list.filter((img) => {
    const haystack =
      `${img.label || ''} ${img.ref || ''} ${img.description || img.desc || ''} ${img.distro || ''} ${img.badge || ''}`.toLowerCase();
    return haystack.includes(query);
  });
}
