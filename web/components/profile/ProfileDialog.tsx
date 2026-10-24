"use client";
import { useTranslation } from "@/lib/i18n";


import { Check, Trash2, X } from "lucide-react";
import { useEffect, useState } from "react";
import { avatarCategories, avatarGradient, avatarSrc, colorToCss, profileColors } from "@/lib/profiles";
import type { Profile } from "@/lib/types";
import { DEFAULT_KIDS_LEVEL, KIDS_LEVELS, kidsLevelOf, type KidsAgeLevel } from "@/lib/kids";
import { hashProfilePin, isValidProfilePin } from "@/lib/profilePin";

/** Kids settings saved with the profile; same fields Android writes (Profile.kt). */
export interface KidsProfileFields {
  isKidsProfile: boolean;
  kidsAgeLevel: KidsAgeLevel | null;
  parentPin: string | null;
}

export function ProfileDialog({ mode, initial, onConfirm, onDelete, onClose }: {
  mode: "add" | "edit";
  initial?: Profile;
  onConfirm: (name: string, avatarColor: number, avatarId: number, kids: KidsProfileFields) => void;
  onDelete?: () => void;
  onClose: () => void;
}) {
  const translateUi = useTranslation();
  const [name, setName] = useState(initial?.name ?? "");
  const [avatarColor, setAvatarColor] = useState(initial?.avatarColor ?? profileColors[0]);
  const [avatarId, setAvatarId] = useState(initial?.avatarId ?? 0);
  const [kidsOn, setKidsOn] = useState(Boolean(initial?.isKidsProfile));
  const [kidsLevel, setKidsLevel] = useState<KidsAgeLevel>(kidsLevelOf(initial) ?? DEFAULT_KIDS_LEVEL);
  const [parentPin, setParentPin] = useState("");
  const [saving, setSaving] = useState(false);
  // A kids profile always has a parent PIN: an existing one is kept, a new one must be set here.
  const needsParentPin = kidsOn && !initial?.parentPin;
  const pinMissing = needsParentPin && !isValidProfilePin(parentPin);

  const confirm = async () => {
    if (saving || !name.trim() || pinMissing) return;
    setSaving(true);
    try {
      const pin = kidsOn ? (needsParentPin ? await hashProfilePin(parentPin) : initial?.parentPin ?? null) : null;
      onConfirm(name.trim() || "Profile", avatarColor, avatarId, {
        isKidsProfile: kidsOn,
        kidsAgeLevel: kidsOn ? kidsLevel : null,
        parentPin: pin
      });
    } finally {
      setSaving(false);
    }
  };

  // Escape / remote Back / gamepad B closes the dialog like every other
  // modal. When the event targets the name input, tvNav already turned that
  // press into a blur — the next one closes.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      const target = event.target;
      if (target instanceof HTMLElement && (target.tagName === "INPUT" || target.tagName === "TEXTAREA")) return;
      onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="profile-dialog" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()}>
        <div className="profile-dialog-head">
          <h2>{mode === "add" ? translateUi("Add Profile") : translateUi("Edit Profile")}</h2>
          <button type="button" className="icon-button" onClick={onClose} aria-label={translateUi("Close")}><X size={20} /></button>
        </div>

        <div className="profile-dialog-preview">
          <div className="avatar-tile lg">
            {avatarId > 0 ? (
              <div className="avatar-visual" style={{ background: `linear-gradient(180deg, ${avatarGradient(avatarId)[0]}, ${avatarGradient(avatarId)[1]})` }}>
                <img className="avatar-emoji" src={avatarSrc(avatarId)} alt="" />
              </div>
            ) : (
              <div className="avatar-visual avatar-letter" style={{ background: colorToCss(avatarColor) }}>
                <span>{name.charAt(0)?.toUpperCase() || "?"}</span>
              </div>
            )}
          </div>
        </div>

        <label className="profile-name-label" htmlFor="profile-name">{translateUi("Profile name")}</label>
        <input
          id="profile-name"
          className="profile-name-input"
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder={translateUi("Profile name")}
          autoFocus
          maxLength={20}
        />

        <h3 className="profile-dialog-label">{translateUi("Color (letter avatar)")}</h3>
        <div className="color-row">
          {profileColors.map((color) => (
            <button
              type="button"
              key={color}
              className={`color-dot ${avatarId === 0 && avatarColor === color ? "is-active" : ""}`}
              style={{ background: colorToCss(color) }}
              onClick={() => { setAvatarColor(color); setAvatarId(0); }}
              aria-label={translateUi("Pick color")}
            >
              {avatarId === 0 && avatarColor === color ? <Check size={16} /> : null}
            </button>
          ))}
        </div>

        <h3 className="profile-dialog-label">{translateUi("Avatar")}</h3>
        <div className="avatar-picker">
          {avatarCategories.map((category) => (
            <div className="avatar-category" key={category.label}>
              <span className="avatar-category-label">{translateUi(category.label)}</span>
              <div className="avatar-grid">
                {category.ids.map((id) => (
                  <button
                    type="button"
                    key={id}
                    className={`avatar-cell ${avatarId === id ? "is-active" : ""}`}
                    style={{ background: `linear-gradient(180deg, ${avatarGradient(id)[0]}, ${avatarGradient(id)[1]})` }}
                    onClick={() => setAvatarId(id)}
                  >
                    <img src={avatarSrc(id)} alt="" />
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>

        <h3 className="profile-dialog-label">{translateUi("Kids Profile")}</h3>
        <div className="profile-kids-row" role="group" aria-label={translateUi("Kids Profile")}>
          <button type="button" className={`secondary text-button ${kidsOn ? "is-active" : ""}`} aria-pressed={kidsOn} onClick={() => setKidsOn(true)}>{kidsOn ? <Check size={16} /> : null} {translateUi("On")}</button>
          <button type="button" className={`secondary text-button ${!kidsOn ? "is-active" : ""}`} aria-pressed={!kidsOn} onClick={() => setKidsOn(false)}>{!kidsOn ? <Check size={16} /> : null} {translateUi("Off")}</button>
        </div>
        {kidsOn && (
          <>
            <p className="profile-kids-hint">{translateUi("Only titles rated for this age. Unrated titles and Live TV are hidden.")}</p>
            <h3 className="profile-dialog-label">{translateUi("Max age")}</h3>
            <div className="profile-kids-row" role="radiogroup" aria-label={translateUi("Max age")}>
              {KIDS_LEVELS.map((level) => (
                <button type="button" key={level} role="radio" aria-checked={kidsLevel === level} className={`secondary text-button ${kidsLevel === level ? "is-active" : ""}`} onClick={() => setKidsLevel(level)}>
                  {level === "LITTLE_KIDS" ? translateUi("Up to 7") : level === "OLDER_KIDS" ? translateUi("Up to 10") : translateUi("Up to 14")}
                </button>
              ))}
            </div>
            {needsParentPin && (
              <>
                <label className="profile-name-label" htmlFor="profile-parent-pin">{translateUi("Set a parent PIN for this kids profile")}</label>
                <input
                  id="profile-parent-pin"
                  className="profile-name-input"
                  type="password"
                  inputMode="numeric"
                  autoComplete="new-password"
                  maxLength={5}
                  value={parentPin}
                  onChange={(event) => setParentPin(event.target.value.replace(/\D/g, "").slice(0, 5))}
                  aria-describedby="profile-parent-pin-hint"
                />
                <p id="profile-parent-pin-hint" className="profile-kids-hint">{translateUi("4-5 digits. Needed to change or delete this kids profile, not to watch.")}</p>
              </>
            )}
          </>
        )}

        <div className="profile-dialog-actions">
          {mode === "edit" && onDelete && (
            <button type="button" className="secondary text-button danger" onClick={onDelete}><Trash2 size={18} /> {translateUi(" Delete")}</button>
          )}
          <button type="button" className="secondary text-button" onClick={onClose}>{translateUi("Cancel")}</button>
          <button type="button" className="primary" onClick={() => void confirm()} disabled={!name.trim() || pinMissing || saving}>
            {mode === "add" ? translateUi("Create") : translateUi("Save")}
          </button>
        </div>
      </div>
    </div>
  );
}
