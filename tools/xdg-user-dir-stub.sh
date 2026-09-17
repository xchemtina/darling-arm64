#!/usr/bin/env sh

case "${1:-}" in
	DESKTOP) name=Desktop ;;
	DOWNLOAD) name=Downloads ;;
	PUBLICSHARE) name=Public ;;
	DOCUMENTS) name=Documents ;;
	MUSIC) name=Music ;;
	PICTURES) name=Pictures ;;
	VIDEOS) name=Videos ;;
	*) exit 1 ;;
esac

printf '%s/%s\n' "${HOME:-/tmp}" "$name"
