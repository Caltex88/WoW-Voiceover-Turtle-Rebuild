setfenv(1, VoiceOver)
Version = {}

local CLIENT_VERSION, BUILD, _, INTERFACE_VERSION = GetBuildInfo()

Version.Client    = CLIENT_VERSION
Version.Build     = BUILD
Version.Interface = INTERFACE_VERSION or 0
