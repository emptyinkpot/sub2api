# Sub2API Frontend Design System

This frontend already has a usable Vue 3 + Tailwind component layer. New UI work should extend it instead of creating parallel widgets.

## Canonical Stack

- Vue 3 Composition API with TypeScript.
- Tailwind utilities and shared component classes from `src/style.css`.
- Reusable UI from `src/components/common`.
- Page shells from `src/components/layout`.
- Business cells and account workflows from `src/components/account` and `src/components/admin`.
- Storybook workbenches under `src/stories`.

## Tokens

- Primary action: `primary-*`.
- Neutral surfaces: `gray-*`, `dark-*`.
- Success: `emerald-*` or existing `.btn-success` / status green.
- Warning: `amber-*` or existing warning state.
- Danger: `red-*` or `.btn-danger`.
- Standard radii come from existing classes. Prefer `rounded-xl` for controls and existing `.card` / `.btn` classes for product surfaces.

## Component Contracts

Use these components before adding new ones:

- Text input: `Input.vue`.
- Long text: `TextArea.vue`.
- Select/dropdown: `Select.vue`.
- Boolean setting: `Toggle.vue`.
- Search: `SearchInput.vue`.
- Table: `DataTable.vue`.
- Pagination: `Pagination.vue`.
- Empty state: `EmptyState.vue`.
- Loading: `LoadingSpinner.vue` or `Skeleton.vue`.
- Dialog: `BaseDialog.vue`; destructive confirmation: `ConfirmDialog.vue`.
- Status text: `StatusBadge.vue`.
- Platform/account badges: `PlatformTypeBadge.vue`, `PlatformIcon.vue`, and account cell components.
- Icons: `components/icons/Icon.vue`. Do not inline SVG when an existing icon name works.

## Page Patterns

List pages must use this order:

1. Actions.
2. Filters/search.
3. Table or card list.
4. Pagination.

Prefer `TablePageLayout.vue` for dense admin list pages.

Dashboard pages should use `StatCard.vue` plus domain-specific panels. Avoid landing-page hero layouts in admin/product surfaces.

Form and modal flows should use `BaseDialog.vue` widths:

- `narrow`: confirmation or short prompts.
- `normal`: simple forms.
- `wide`: multi-section forms.
- `extra-wide` / `full`: dense tables or multi-column account editing.

## States

Every reusable workflow needs explicit:

- loading state,
- empty state,
- error or warning state,
- disabled state for unavailable actions,
- mobile behavior.

Tables should define row keys and custom `cell-*` slots for non-trivial cells. Do not put business formatting directly into generic table logic.

## Anti-Patterns

- Do not create a second generic table, modal, select, toast, or input layer.
- Do not add nested cards inside cards.
- Do not use marketing hero composition for admin tools.
- Do not use one-off colors outside Tailwind tokens unless the component already owns a brand color.
- Do not add visible instructional text explaining the UI mechanics.
- Do not mount full API-backed views in Storybook unless API access is mocked.

## Storybook Rules

Storybook should stay local and read the project from `E:\My Project\sub2api\frontend`.

Use these story groups:

- `Project/*`: import maps and project topology.
- `Design System/*`: reusable tokens, controls, layout patterns, and states.
- `Components/*`: focused component workbenches.
- `Workbench/*`: mocked business workflows.

When adding a complex interaction, first create or update a mocked Storybook workbench with realistic data. Then integrate it into the real route.

Run locally:

```bash
pnpm storybook
```

Then open:

```text
http://127.0.0.1:6006/
```
