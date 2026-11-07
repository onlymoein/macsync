/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `sync` command */
  export type Sync = ExtensionPreferences & {}
  /** Preferences accessible in the `pull` command */
  export type Pull = ExtensionPreferences & {}
  /** Preferences accessible in the `undo` command */
  export type Undo = ExtensionPreferences & {}
  /** Preferences accessible in the `status` command */
  export type Status = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `sync` command */
  export type Sync = {}
  /** Arguments passed to the `pull` command */
  export type Pull = {}
  /** Arguments passed to the `undo` command */
  export type Undo = {}
  /** Arguments passed to the `status` command */
  export type Status = {}
}

