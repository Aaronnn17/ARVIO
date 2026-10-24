// Dismissal of the Home "Add a source" banner, per profile. localStorage, not
// sessionStorage: an iPhone home-screen app starts a fresh session on every
// launch, so a session-scoped dismissal brought the banner back each time.
export const SOURCE_PROMPT_KEY_PREFIX = "arvio.web.sourcePrompt.dismissed.v1:";
export const SOURCE_PROMPT_EVENT = "arvio:source-prompt";

function storage(): Storage | null {
  try {
    return typeof window === "undefined" ? null : window.localStorage;
  } catch {
    return null;
  }
}

export function isSourcePromptDismissed(profileId: string): boolean {
  if (!profileId) return false;
  try {
    return storage()?.getItem(`${SOURCE_PROMPT_KEY_PREFIX}${profileId}`) === "1";
  } catch {
    return false;
  }
}

export function setSourcePromptDismissed(profileId: string, dismissed: boolean) {
  if (!profileId) return;
  try {
    const store = storage();
    if (dismissed) store?.setItem(`${SOURCE_PROMPT_KEY_PREFIX}${profileId}`, "1");
    else store?.removeItem(`${SOURCE_PROMPT_KEY_PREFIX}${profileId}`);
  } catch {
    /* storage is optional: the banner then simply returns next launch */
  }
  try {
    window.dispatchEvent(new CustomEvent(SOURCE_PROMPT_EVENT, { detail: { profileId, dismissed } }));
  } catch {
    /* no window (tests) */
  }
}
