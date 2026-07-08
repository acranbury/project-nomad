import Service from '#models/service'

export type ServiceSlim = Pick<
  Service,
  | 'id'
  | 'service_name'
  | 'installed'
  | 'installation_status'
  | 'ui_location'
  | 'custom_url'
  | 'friendly_name'
  | 'description'
  | 'icon'
  | 'powered_by'
  | 'display_order'
  | 'container_image'
  | 'available_update_version'
  | 'auto_update_enabled'
  | 'is_custom'
  | 'is_user_modified'
  | 'is_deprecated'
  | 'category'
> & {
  status?: string
  // True when this app has no published linux/arm64 image and is running under
  // Rosetta 2 emulation on this (arm64) host. See constants/arch.ts.
  emulated?: boolean
}
