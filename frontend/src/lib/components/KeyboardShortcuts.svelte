<script>
  import { navigate, getRoute } from '$lib/router.svelte.js';
  import { t } from '$lib/i18n.svelte.js';
  import * as Dialog from '$lib/components/ui/dialog';

  let show = $state(false);

  // Group "g x" navigation: pressing g then a letter within 1.2s
  // navigates to that route.
  let gPrefix = false;
  let gPrefixTimer = null;

  function flashGPrefix() {
    gPrefix = true;
    clearTimeout(gPrefixTimer);
    gPrefixTimer = setTimeout(() => (gPrefix = false), 1200);
  }

  function onKey(e) {
    // Skip when an input/textarea has focus (so /, g, ?, c
    // don't break form fields). Skip if a modifier is held
    // (⌘K already works through the CommandPalette).
    const t = e.target;
    const isFormField =
      t &&
      (t.tagName === 'INPUT' ||
        t.tagName === 'TEXTAREA' ||
        t.tagName === 'SELECT' ||
        t.isContentEditable);
    if (isFormField) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    // Global shortcuts.
    if (e.key === '?') {
      e.preventDefault();
      show = !show;
      return;
    }
    if (e.key === 'g') {
      flashGPrefix();
      return;
    }
    if (gPrefix) {
      const map = { v: '/vms', s: '/storage', n: '/networks', u: '/users', a: '/account' };
      if (map[e.key]) {
        e.preventDefault();
        navigate(map[e.key]);
        clearTimeout(gPrefixTimer);
        gPrefix = false;
        return;
      }
    }
    // "/" — focus the first search input on the page. Currently
    // only the VMs list has one; fall back to opening the
    // command palette.
    if (e.key === '/') {
      e.preventDefault();
      const sel = document.querySelector('input[type="search"]');
      if (sel) {
        sel.focus();
        sel.select();
      } else {
        window.dispatchEvent(new CustomEvent('open-command-palette'));
      }
    }
    // "c" — create VM.
    if (e.key === 'c' && !gPrefix) {
      const route = getRoute();
      if (route.name === 'vms' || route.name === 'vm-detail') {
        e.preventDefault();
        navigate('/vms/new');
      }
    }
  }

  $effect(() => {
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      // Cancel any pending "g x" prefix timer on unmount.
      if (gPrefixTimer) clearTimeout(gPrefixTimer);
      gPrefixTimer = null;
    };
  });

  const groups = [
    {
      labelKey: 'keyboardShortcuts.groupNavigation',
      shortcuts: [
        { keys: ['g', 'v'], descKey: 'keyboardShortcuts.goToVms' },
        { keys: ['g', 's'], descKey: 'keyboardShortcuts.goToStorage' },
        { keys: ['g', 'n'], descKey: 'keyboardShortcuts.goToNetworks' },
        { keys: ['g', 'u'], descKey: 'keyboardShortcuts.goToUsers' },
        { keys: ['g', 'a'], descKey: 'keyboardShortcuts.goToAccount' },
      ],
    },
    {
      labelKey: 'keyboardShortcuts.groupActions',
      shortcuts: [
        { keys: ['/'], descKey: 'keyboardShortcuts.focusSearch' },
        { keys: ['c'], descKey: 'keyboardShortcuts.createVm' },
        { keys: ['Esc'], descKey: 'keyboardShortcuts.closeDialogs' },
      ],
    },
    {
      labelKey: 'keyboardShortcuts.groupHelp',
      shortcuts: [
        { keys: ['⌘', 'K'], descKey: 'keyboardShortcuts.openCommandPalette' },
        { keys: ['?'], descKey: 'keyboardShortcuts.showCheatsheet' },
      ],
    },
  ];
</script>

<Dialog.Root open={show} onOpenChange={(v) => (show = v)}>
  <Dialog.Content class="sm:max-w-md">
    <Dialog.Header>
      <Dialog.Title>{t('keyboardShortcuts.title')}</Dialog.Title>
      <Dialog.Description
        >{t('keyboardShortcuts.descPrefix')}
        <kbd class="text-xs font-mono px-1.5 py-0.5 rounded bg-muted">?</kbd>
        {t('keyboardShortcuts.descSuffix')}</Dialog.Description
      >
    </Dialog.Header>
    <div class="space-y-4 py-2">
      {#each groups as g (g.labelKey)}
        <div>
          <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
            {t(g.labelKey)}
          </div>
          <div class="space-y-1">
            {#each g.shortcuts as s (s.descKey)}
              <div
                class="flex items-center justify-between text-sm py-1 border-b border-border/50 last:border-0"
              >
                <span class="text-muted-foreground">{t(s.descKey)}</span>
                <span class="flex items-center gap-1">
                  {#each s.keys as k, i (k)}
                    <kbd
                      class="text-xs font-mono px-1.5 py-0.5 rounded bg-muted border border-border text-foreground min-w-[1.5rem] text-center"
                      >{k}</kbd
                    >
                    {#if i < s.keys.length - 1}<span class="text-muted-foreground text-xs">+</span
                      >{/if}
                  {/each}
                </span>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  </Dialog.Content>
</Dialog.Root>
