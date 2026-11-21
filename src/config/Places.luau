-- Place table (spec: Fly-in planet travel). Phase 1 is one place; Phase 3 adds the moon Calder as its own
-- place reached by flying through the orbit ring. Ids are filled in by nate when the places are published.
-- 2026-11-21 (Everything Left 736): the orbit, Calder and the alien planet are built as zones in this place for
-- now (Config.Space, SpaceService); a world whose placeId is set here can later move to its own place, reached by
-- the same rings and entry (the arrival burst plays as that place's loading screen, spec).
return {
	Brightharbor = { placeId = 0, role = "City" },
	Calder = { placeId = 0, role = "Planet", phase = 3 },
	Thalyx = { placeId = 0, role = "Planet", phase = 3 }, -- the alien planet (DRAFT name)
	Ironmere = { placeId = 0, role = "City", phase = 2 },
}
