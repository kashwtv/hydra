import { ChevronDownIcon } from "@primer/octicons-react";
import { useEffect, useRef, useState } from "react";
import { CheckboxField } from "@renderer/components/checkbox-field/checkbox-field";
import { useTranslation } from "react-i18next";

interface MacCompatibilitySectionProps {
  color: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

export function MacCompatibilitySection({
  color,
  checked,
  onChange,
}: MacCompatibilitySectionProps) {
  const [isOpen, setIsOpen] = useState(true);
  const [height, setHeight] = useState(0);
  const content = useRef<HTMLDivElement>(null);
  const { t } = useTranslation("catalogue");

  useEffect(() => {
    if (content.current) {
      setHeight(isOpen ? content.current.scrollHeight : 0);
    }
  }, [isOpen, checked]);

  return (
    <div className="filter-section proton-compatibility-section">
      <button
        type="button"
        className="filter-section__button"
        onClick={() => setIsOpen((open) => !open)}
        aria-expanded={isOpen}
      >
        <ChevronDownIcon
          className={`filter-section__chevron ${
            isOpen ? "filter-section__chevron--open" : ""
          }`}
        />

        <div className="filter-section__header">
          <div
            className="filter-section__orb"
            style={{ backgroundColor: color }}
          />
          <h3 className="filter-section__title">{t("macos_compatibility")}</h3>
        </div>
      </button>

      <div
        ref={content}
        className="filter-section__content"
        style={{ maxHeight: `${height}px` }}
      >
        <div className="filter-section__content-inner proton-compatibility-section__content-inner">
          <div className="proton-compatibility-section__control">
            <span className="proton-compatibility-section__label">
              {t("macos_native_support_label")}
            </span>

            <CheckboxField
              label={t("macos_native_supported")}
              checked={checked}
              onChange={(event) => onChange(event.target.checked)}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
