/*
This file is part of ZalupaGram, a fork of Telegram Desktop.

For license and copyright information please follow this link:
https://github.com/telegramdesktop/tdesktop/blob/master/LEGAL
*/
#pragma once

// The animated pixel sky of the «Night sky» themes: a software renderer of
// a small grid of big pixels, no dependencies, the same file in ZalupaGram
// Desktop and iOS. The app scales the grid up without smoothing, gives it
// the local time and tells what happens in the messenger.

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZgSky ZgSky;

enum {
	ZG_SKY_MODE_CYCLE = 0, // Follows the clock of the device.
	ZG_SKY_MODE_NIGHT = 1,
	ZG_SKY_MODE_DAY = 2,
};

enum {
	ZG_SKY_WEATHER_AUTO = 0, // Random by the season.
	ZG_SKY_WEATHER_CLEAR = 1,
	ZG_SKY_WEATHER_RAIN = 2,
	ZG_SKY_WEATHER_STORM = 3,
	ZG_SKY_WEATHER_SNOW = 4,
	ZG_SKY_WEATHER_BLIZZARD = 5,
	ZG_SKY_WEATHER_FOG = 6,
	ZG_SKY_WEATHER_WIND = 7,
};

enum {
	ZG_SKY_FIRE_SENT = 0, // Paper plane from the input field.
	ZG_SKY_FIRE_REACTION = 1, // Small firework.
	ZG_SKY_FIRE_RECEIVED = 2, // Pigeon with a letter.
	ZG_SKY_FIRE_DELETED = 3, // Meteorite into a hill.
	ZG_SKY_FIRE_CONGRATS = 4, // Golden shooting star.
	ZG_SKY_FIRE_VOICE = 5, // Banana rocket.
	ZG_SKY_FIRE_BIRTHDAY = 6, // Banner and fireworks.
};

typedef struct ZgSkyRect {
	int x;
	int y;
	int width;
	int height;
} ZgSkyRect;

ZgSky *zg_sky_create(void);
void zg_sky_destroy(ZgSky *sky);

// The size of the grid, in big pixels.
void zg_sky_set_size(ZgSky *sky, int cols, int rows);
void zg_sky_set_mode(ZgSky *sky, int mode);
void zg_sky_set_weather(ZgSky *sky, int weather);
// A chat is open: the sky is dimmed by `dim` (0..1), with a softer horizon.
void zg_sky_set_chat(ZgSky *sky, int chat_open, float dim, int soft);
// Without events only the sky itself changes, with the time of day.
void zg_sky_set_events(ZgSky *sky, int enabled);
void zg_sky_set_ghost(ZgSky *sky, int enabled);
// Automatic events run this much more often, for looking at them.
void zg_sky_set_event_rate(ZgSky *sky, float rate);
// From -1 to 1, the mouse position or the tilt of the phone.
void zg_sky_set_parallax(ZgSky *sky, float x, float y);
// Input field position on the sky for the plane of a sent message, 0..1.
void zg_sky_set_launch_point(ZgSky *sky, float x, float y);
// The local date, month from 0, and minutes since the local midnight.
void zg_sky_set_time(
	ZgSky *sky,
	int year,
	int month,
	int day,
	double minutes);
void zg_sky_fire(ZgSky *sky, int what);

// Runs the sky for `seconds`, renders it and returns the number of changed
// rects, up to `max_rects` of them are written to `rects`.
int zg_sky_advance(
	ZgSky *sky,
	double seconds,
	ZgSkyRect *rects,
	int max_rects);
// Opaque pixels, 0xFFRRGGBB, cols * rows of them, row by row.
const uint32_t *zg_sky_pixels(const ZgSky *sky);
// How long to wait before the next zg_sky_advance.
int zg_sky_next_delay_ms(const ZgSky *sky);
// The name of a rare event at this cell, UTF-8, or null if there is none.
const char *zg_sky_catch(const ZgSky *sky, int col, int row);

#ifdef __cplusplus
} // extern "C"
#endif
