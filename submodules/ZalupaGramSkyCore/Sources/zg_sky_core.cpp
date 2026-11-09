/*
This file is part of ZalupaGram, a fork of Telegram Desktop.

For license and copyright information please follow this link:
https://github.com/telegramdesktop/tdesktop/blob/master/LEGAL
*/
#include "zg_sky_core.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <functional>
#include <limits>
#include <random>
#include <string>
#include <vector>

namespace {

constexpr auto kPi = 3.14159265358979323846;
constexpr auto kSaintPetersburgLatitude = 59.9343;
constexpr auto kSaintPetersburgLongitude = 30.3351;
constexpr auto kSaintPetersburgUtcMinutes = 180.;
constexpr auto kHolidayOtherMean = 144000.;
constexpr auto kNoValue = std::numeric_limits<int>::min();
constexpr auto kHillMargin = 4; // Hill columns outside of the grid, parallax.
constexpr auto kTile = 12; // Changed rects are multiples of this, in cells.
constexpr auto kPaletteInterval = 20.; // Seconds between sky color updates.

struct Col {
	float r = 0.f;
	float g = 0.f;
	float b = 0.f;
};

[[nodiscard]] constexpr Col C(uint32_t rgb) {
	return Col{
		float((rgb >> 16) & 0xFF),
		float((rgb >> 8) & 0xFF),
		float(rgb & 0xFF) };
}

[[nodiscard]] Col Mix(Col a, Col b, double t) {
	const auto f = float(t);
	return Col{
		a.r + (b.r - a.r) * f,
		a.g + (b.g - a.g) * f,
		a.b + (b.b - a.b) * f };
}

using Sprite = std::vector<std::string>;
using Frames = std::vector<Sprite>;

struct Pal {
	std::array<int64_t, 128> colors;
	Pal(std::initializer_list<std::pair<char, uint32_t>> list) {
		colors.fill(-1);
		for (const auto &[key, value] : list) {
			colors[int(key)] = value;
		}
	}
};

struct KeyFrame {
	int time = 0;
	std::array<Col, 8> sky;
	std::array<Col, 4> hill;
	Col cloud;
	double cloudAlpha = 0.;
	double star = 0.;
};

[[nodiscard]] const std::vector<KeyFrame> &KeyFrames() {
	static const auto night = KeyFrame{
		0,
		{ C(0x0B0F4F), C(0x10146A), C(0x1A179A), C(0x2A1BB8),
			C(0x4A1ED0), C(0x7A24E4), C(0xB02CF0), C(0xE43EF2) },
		{ C(0x3E3FC8), C(0x2B2B9E), C(0x1D1E78), C(0x0D1060) },
		C(0x7A24E4),
		0.,
		1. };
	const auto nightAt = [&](int time) {
		auto result = night;
		result.time = time;
		return result;
	};
	static const auto result = std::vector<KeyFrame>{
		nightAt(0),
		nightAt(270),
		KeyFrame{ 345,
			{ C(0x1B1F6B), C(0x2F2F8E), C(0x5A3FB0), C(0x8E55C4),
				C(0xC86FB8), C(0xF08FA0), C(0xFFB38A), C(0xFFD68A) },
			{ C(0x6A4FA8), C(0x4A3A8C), C(0x2F2A6E), C(0x1C1B52) },
			C(0xF8B6C8), .55, .35 },
		KeyFrame{ 420,
			{ C(0x3E7FD8), C(0x5A96E2), C(0x78ADEA), C(0x95C2F0),
				C(0xB2D5F4), C(0xCDE4F6), C(0xE6F0F5), C(0xFBEFD0) },
			{ C(0x5E9F8A), C(0x3F8A78), C(0x2C7262), C(0x1C5A4C) },
			C(0xFFFFFF), .85, 0. },
		KeyFrame{ 720,
			{ C(0x2A74D6), C(0x3C84DE), C(0x4F95E6), C(0x64A6EC),
				C(0x7BB6F0), C(0x95C6F4), C(0xB3D7F7), C(0xD3E8FA) },
			{ C(0x4FA06A), C(0x3A8A5C), C(0x2A7050), C(0x1D5840) },
			C(0xFFFFFF), .95, 0. },
		KeyFrame{ 1020,
			{ C(0x3770C8), C(0x4C84D2), C(0x6699DB), C(0x86ADDF),
				C(0xA9BFDD), C(0xCFCFD0), C(0xEEDAB8), C(0xFBD9A0) },
			{ C(0x5E9A62), C(0x477F55), C(0x336648), C(0x234E3A) },
			C(0xFFF3DC), .9, 0. },
		KeyFrame{ 1140,
			{ C(0x2B2A78), C(0x4A3595), C(0x7A3FA8), C(0xB04AA8),
				C(0xE05F96), C(0xF57E76), C(0xFBA15C), C(0xFFC14D) },
			{ C(0x7A4A8C), C(0x5A3A78), C(0x3E2A62), C(0x261C4A) },
			C(0xFFB0A0), .75, .1 },
		KeyFrame{ 1230,
			{ C(0x12145C), C(0x1D1C7E), C(0x33259C), C(0x5A2BB4),
				C(0x8A2FC0), C(0xBA3ACB), C(0xE04AC8), C(0xF06BA8) },
			{ C(0x3E2F9E), C(0x2D2484), C(0x201A68), C(0x13114E) },
			C(0x9A5FD0), .25, .7 },
		nightAt(1320),
		nightAt(1440),
	};
	return result;
}

const Sprite kJet = {
	"TT......................",
	"TTT.....................",
	"TTTT....................",
	".TTTWWWWWWWWWWWWWWWWW...",
	".WWWWDWDWDWDWDWDWDWWWCC.",
	".BBBBBBBBBBBBBBBBBBBBBBB",
	"..GGGGGGGGGGGGGGGGGGGGG.",
	"........KKKKKKK.........",
	"........EEKKKK..........",
	"...........KKK.........." };
const Sprite kSatellite = {
	".........A.........",
	"........AAA........",
	"PpPpPp...B...PpPpPp",
	"PpPpPp=SSSSS=PpPpPp",
	"PpPpPp.SSSSS.PpPpPp",
	"PpPpPp..SSS..PpPpPp",
	".........d........." };
const Sprite kPaper = {
	".......W",
	"....WWWW",
	"..WWWLLW",
	"WWWWLLW.",
	"..WLLWW.",
	"..LDWWW.",
	"..D..W.." };
const Sprite kBalloon = {
	"...RRRRR...",
	"..RRWWWRR..",
	".RRRWWWRRR.",
	"RRRRWWWRRRR",
	"RRRRWWWRRRR",
	"RRRRWWWRRRR",
	".RRRWWWRRR.",
	"..RRWWWRR..",
	"...RRWRR...",
	"....RWR....",
	"....B.B....",
	"....B.B....",
	"....TTT....",
	"....TTT...." };
const Sprite kCatBalloon = {
	"...RRRRR...",
	"..RRWWWRR..",
	".RRRWWWRRR.",
	"RRRRWWWRRRR",
	"RRRRWWWRRRR",
	"RRRRWWWRRRR",
	".RRRWWWRRR.",
	"..RRWWWRR..",
	"...RRWRR...",
	"....RWR....",
	"....B.B....",
	"....B.B....",
	"...KTTTK...",
	"...KKKKK...",
	"....TTT....",
	"....TTT...." };
const Sprite kAirship = {
	"F...SSSSSSSSSSSSSSSSSSS...",
	"FF.SSSSSSSSSSSSSSSSSSSSSS.",
	"FFSSSSSSSSSSSSSSSSSSSSSSSS",
	"FSSSSSSSSSSSSSSSSSSSSSSSSS",
	"FFSSSSSSSSSSSSSSSSSSSSSSSS",
	"FF.SSSSSSSSSSSSSSSSSSSSSS.",
	"F...SSSSSSSSSSSSSSSSSSS...",
	"...........GGGGGG.........",
	"...........GDGDGG........." };
const Frames kHelicopter = {
	{
		"RRRRRRRRRRRRRRRRR...",
		"........M...........",
		"T....BBBBBBBBB......",
		"TBBBBBBBBBBWWWB.....",
		"T....BBBBBBBBBB.....",
		"......G.....G.......",
		".....GGGGGGGGGG....." },
	{
		"....RRRRRRRRR.......",
		"........M...........",
		"Y....BBBBBBBBB......",
		"YBBBBBBBBBBWWWB.....",
		"T....BBBBBBBBBB.....",
		"......G.....G.......",
		".....GGGGGGGGGG....." } };
const Sprite kCanopy = {
	"..RRRRRRR..",
	".RRWWWWWRR.",
	"RRRRRRRRRRR",
	".L.......L.",
	"..L.....L..",
	"...L...L...",
	"....L.L....",
	".....P.....",
	"....PPP....",
	".....P.....",
	"....P.P...." };
const Frames kSheep = {
	{ ".WWWW.", "WWWWWK", "WWWWW.", "K..K.." },
	{ ".WWWW.", "WWWWWK", "WWWWW.", ".K..K." } };
const Frames kRooster = {
	{ "..R...", ".RWW..", ".WWWY.", "TWWW..", "TWWW..", "..L...", "..LL.." },
	{ "..R...", ".RWWY.", ".WWW..", "TWWW..", "TWWW..", "..L...", "..LL.." } };
const Frames kWolf = {
	{ ".....K..", "....KK..", "...KKKK.", "KKKKKK..", "KKKKKK..", "K.K..K.." },
	{ ".....K..", ".....KK.", "...KKKKK", "KKKKKK..", "KKKKKK..", "K.K..K.." } };
const Frames kOwl = {
	{ "W.....W", "WW.B.WW", ".WWBWW.", "..WWW..", "...T..." },
	{ ".......", ".WWBWW.", "WWWBWWW", "W.WWW.W", "...T..." } };
const Sprite kRocket = {
	"..W..", ".WRW.", ".WWW.", ".WBW.", ".WWW.", "WWWWW", "W.W.W" };
const Sprite kRocketTop = { "..W..", ".WRW.", ".WWW.", ".WBW.", ".WWW." };
const Sprite kRocketStage = { "WWWWW", "W.W.W" };
const Sprite kWhale = {
	"........BBBBBBBB........",
	".....BBBBBBBBBBBBBB...T.T",
	"...BBBBBBBBBBBBBBBBBB.TTT",
	"..BBWBBBBBBBBBBBBBBBBBBT.",
	".BBBBBBBBBBBBBBBBBBBBB...",
	"LLLLLLLLLLLLLLLLLLLLB....",
	"..LLLLLLLLLLLLLLLLL......",
	"....LLLLLLLLLL..........." };
const Sprite kShip = {
	".......M.......",
	"...SSSMMSSS....",
	"..SSSSSMSSSSS..",
	"..SSSSSMSSSSS..",
	"...SSSSMSSSS...",
	".......M.......",
	"HHHHHHHHHHHHHHH",
	".HHHHHHHHHHHHH.",
	"..HHHHHHHHHHH.." };
const Sprite kCat = { ".K.K.", "KKKKK", "KGKGK", "KKKKK", ".KKK.", ".KKK." };
const Sprite kDino = {
	"...GGGGGG.",
	"..GGKGGGGG",
	"..GGGGGGGG",
	"..GGGGGWW.",
	"..GGGG....",
	".GGGGG....",
	"GGGGGG....",
	"GGGGGG...." };
const Sprite kHero = {
	"......SS.",
	"CCCC.BBSS",
	"CCCCBBBBB",
	".CCBBBBBB",
	"..C.BB...",
	"....RR..." };
const Sprite kWitch = {
	"....H.....",
	"...HHH....",
	"..HHHHH.K.",
	".BBKKKK...",
	"BBBBBBBBBB",
	".......T.." };
const Sprite kSanta = {
	"RR........B.B",
	"RRW....BBBB..",
	"RRRRR..BBBBB.",
	"GGGGG.BBBBBB.",
	"..G....B..B.." };
const Frames kPigeon = {
	{ "..GG....", ".GGGGW..", "GGGGGGY.", "..GG....", "..EE...." },
	{ "..GGG...", ".GGGGW..", "GGGGGGY.", "........", "..EE...." } };
const Sprite kGhost = {
	".WWWW.", "WWWWWW", "WDWWDW", "WWWWWW", "WWWWWW", "W.WW.W" };
const Sprite kBanana = {
	".....YY",
	"....YYY",
	"...YYY.",
	"..YYY..",
	".YYY...",
	"YYY....",
	"FF....." };
const Sprite kCow = {
	"WW.....K", "WKKWWWWW", "WWWKKWWW", "WWWWWWW.", "K.K..K.K" };
const Sprite kSnowman = {
	"..KK..",
	"..KK..",
	".WWWW.",
	".WKWW.",
	".WWWO.",
	"..WW..",
	".WWWW.",
	"WWWWWW",
	"WWWWWW",
	".WWWW." };
const Sprite kTree = {
	"...G...",
	"..GGG..",
	".GGGGG.",
	"..GGG..",
	".GGGGG.",
	"GGGGGGG",
	"...B..." };
const Sprite kTent = {
	"....O....",
	"...OOO...",
	"..OOKOO..",
	".OOOKOOO.",
	"OOOOKOOOO" };
const Sprite kSkier = { ".R..", "RRR.", ".K..", "K.K.", "SSSS" };
const Sprite kHeart = {
	".RR.RR.",
	"RRRRRRR",
	"RRRRRRR",
	".RRRRR.",
	"..RRR..",
	"...R..." };
const Sprite kUfo = {
	"...CCC...",
	"..CCCCC..",
	".SSSSSSS.",
	"SSSSSSSSS",
	".YSYSYSY." };
const Sprite kKite = {
	"...R...",
	"..RRR..",
	".RRYRR.",
	"RRYYYRR",
	".YYYYY.",
	"..YYY..",
	"...Y..." };

[[nodiscard]] const char *Glyph(char32_t ch) {
	switch (ch) {
	case U'Z': return "111001010100111";
	case U'A': return "010101111101101";
	case U'L': return "100100100100111";
	case U'U': return "101101101101111";
	case U'P': return "110101110100100";
	case U'G': return "011100101101011";
	case U'R': return "110101110101101";
	case U'M': return "101111111101101";
	case U'Л': return "011101101101101";
	case U'Е': return "111100110100111";
	case U'Г': return "111100100100100";
	case U'И': return "101101111111101";
	case U'О': return "111101101101111";
	case U'Н': return "101101111101101";
	case U'С': return "111100100100111";
	case U'Д': return "010101101111101";
	case U'Р': return "110101110100100";
	}
	return "000000000000000";
}

enum class Id {
	Sent, Reaction, Pigeon, Ghost, Deleted, Congrats, Banana,
	Meteor, Shower, Comet, Satellite, Chain, Ufo, Aurora, Flies, Bats, Owl,
	Wolf, Constellation, Rocket, Whale, Ship, CatMoon, Lunar, Camp, Train,
	Jet, Banner, Birds, Balloon, Airship, Helicopter, Parachute, Kite, Sheep,
	Rooster, FogLow, Solar, RedMoon, Home, Cranes, Geese, Petals, Leaves,
	Hearts, AprilFirst, AprilTwelfth, Witch, ZgBirthday, MyBirthday, NewYear,
	Santa, Legion, Cow, CatBalloon, Dino, Hero, Skier, Flash, Rainbow,
	Burst, Rise, Fireworks,
};

struct Ev {
	Id id = Id::Burst;
	int layer = 0;
	double t = 0.;
	const char *rare = nullptr;
	int bx = 0;
	int by = 0;
	int bw = 0;
	int bh = 0;
	double px = 0.;
	double py = 0.;
	double a = 0.;
	double b = 0.;
	double c = 0.;
	std::vector<std::array<double, 4>> list;
	std::function<bool(Ev&, double)> update;
	std::function<void(Ev&)> paint;
};

struct Moving {
	int dir = 1;
	double speed = 6.;
	double fps = 4.;
	double bob = 0.;
	int tail = 0;
	double alpha = 0.;
	int x = kNoValue;
	int y = kNoValue;
	double vy = 0.;
	const char *rare = nullptr;
	int layer = 0;
	std::function<void(Ev&, int, int, int)> pre;
	std::function<void(Ev&, int, int, int)> post;
};

// An event has a constant chance to start at any moment. There is no countdown,
// so closing the app never loses any progress towards a rare event.
struct Automatic {
	Id id = Id::Meteor;
	double mean = 0.; // Seconds of the sky on screen between two events, at its time.
	double otherMean = 0.; // The same at any other time, never if zero.
	std::function<bool()> favorable;
	std::function<bool()> possible; // Only when it can't be drawn otherwise.
};

struct Star {
	int x = 0;
	int y = 0;
	double phase = 0.;
	double period = 0.;
	bool big = false;
};

struct Cloud {
	double x = 0.;
	double y = 0.;
	int width = 0;
};

struct LitWindow {
	int x = 0;
	int y = 0;
	int on = 0;
	int off = 0;
};

struct CityLight {
	int x = 0;
	int y = 0;
	int on = 0;
};

struct Flower {
	int x = 0;
	int layer = 0;
	int dy = 0;
	uint32_t color = 0;
};

struct Drop {
	double x = 0.;
	double y = 0.;
	double d = 0.;
	double v = 0.;
	uint32_t color = 0;
};

struct Palette {
	std::array<Col, 8> sky;
	std::array<Col, 4> hill;
	Col cloud;
	double cloudAlpha = 0.;
	double star = 0.;
};

} // namespace

struct ZgSky {
	int W = 0;
	int H = 0;
	double k = 1.;
	std::vector<uint32_t> pixels;
	std::vector<uint32_t> previous;
	bool fullRepaint = true;
	double alpha = 1.;

	int mode = ZG_SKY_MODE_NIGHT;
	int weatherSetting = ZG_SKY_WEATHER_AUTO;
	bool chatOpen = false;
	float dim = 0.f;
	bool soft = true;
	bool eventsEnabled = true;
	bool ghost = false;
	double eventRate = 2.;
	double parallaxX = 0.;
	double parallaxY = 0.;
	double launchX = .25;
	double launchY = .92;
	int year = 2026;
	int month = 0;
	int day = 1;
	double minutes = 720.;
	mutable int sunTimesDay = -1;
	mutable double sunriseMinutes = 0.;
	mutable double sunsetMinutes = 0.;

	double T = 0.;
	double flash = 0.;
	double flipUntil = -1.;
	double solarCover = 0.;
	double lunarRed = 0.;
	double forceFull = 0.;
	double paletteAge = kPaletteInterval;
	double boltTimer = 4.;
	double boltLeft = 0.;
	std::vector<std::array<int, 4>> bolt;
	int lastWeather = ZG_SKY_WEATHER_CLEAR;
	int eclipseDay = -1;

	std::mt19937 engine{ std::random_device{}() };
	std::vector<Ev> events;
	std::vector<Automatic> automatic;
	std::vector<std::function<void()>> pendingEvents;
	struct Delayed {
		double at = 0.;
		std::function<void()> callback;
	};
	std::vector<Delayed> delayed;

	std::vector<Star> stars;
	std::array<std::vector<int>, 3> hills;
	std::vector<LitWindow> windows;
	std::vector<Cloud> clouds;
	std::vector<CityLight> city;
	std::vector<Flower> flowers;
	std::vector<Drop> drops;
	std::vector<Drop> petals;
	bool petalsAreLeaves = false;
	double petalsLeft = 0.;
	Palette palette;
	int hillOffsetX[3] = { 0, 0, 0 };
	int hillOffsetY = 0;
	int skyOffsetX = 0;

	int R(int n) {
		return (n > 0) ? int(engine() % uint32_t(n)) : 0;
	}
	// A uniform number in [0, 1) with 53 random bits. Not generate_canonical:
	// a recent MSVC STL gives it only the asked 16 bits, so every chance
	// below 1/65536 a tick became 1/65536 and rare events came every minute.
	double F() {
		const auto high = uint64_t(engine() >> 5);
		const auto low = uint64_t(engine() >> 6);
		return double((high << 26) | low) * (1. / 9007199254740992.);
	}

	// ---------- painting ----------
	void put(int x, int y, Col c) {
		if (x < 0 || y < 0 || x >= W || y >= H) {
			return;
		}
		auto &pixel = pixels[y * W + x];
		if (alpha >= 1.) {
			pixel = 0xFF000000U
				| (uint32_t(c.r) << 16)
				| (uint32_t(c.g) << 8)
				| uint32_t(c.b);
		} else {
			const auto was = Col{
				float((pixel >> 16) & 0xFF),
				float((pixel >> 8) & 0xFF),
				float(pixel & 0xFF) };
			const auto now = Mix(was, c, alpha);
			pixel = 0xFF000000U
				| (uint32_t(now.r) << 16)
				| (uint32_t(now.g) << 8)
				| uint32_t(now.b);
		}
	}
	void rect(Col c, int x, int y, int w, int h) {
		const auto x1 = std::min(x + w, W);
		const auto y1 = std::min(y + h, H);
		for (auto j = std::max(y, 0); j < y1; ++j) {
			for (auto i = std::max(x, 0); i < x1; ++i) {
				put(i, j, c);
			}
		}
	}
	void rect(uint32_t c, int x, int y, int w, int h) {
		rect(C(c), x, y, w, h);
	}
	void disc(Col c, int cx, int cy, int r) {
		for (auto dy = -r; dy <= r; ++dy) {
			for (auto dx = -r; dx <= r; ++dx) {
				if (dx * dx + dy * dy <= r * r) {
					put(cx + dx, cy + dy, c);
				}
			}
		}
	}
	void sprite(const Sprite &s, int x, int y, const Pal &pal, bool flip = false) {
		for (auto j = 0; j != int(s.size()); ++j) {
			const auto &row = s[j];
			const auto n = int(row.size());
			for (auto i = 0; i != n; ++i) {
				const auto color = pal.colors[int(row[i]) & 0x7F];
				if (color >= 0) {
					put(x + (flip ? (n - 1 - i) : i), y + j, C(uint32_t(color)));
				}
			}
		}
	}
	void text(const std::u32string &s, int x, int y, uint32_t color) {
		for (auto i = 0; i != int(s.size()); ++i) {
			const auto glyph = Glyph(s[i]);
			for (auto q = 0; q != 15; ++q) {
				if (glyph[q] == '1') {
					put(x + i * 4 + q % 3, y + q / 3, C(color));
				}
			}
		}
	}

	// ---------- calendar and time of day ----------
	[[nodiscard]] static int DaysFromCivil(int y, int m, int d) {
		y -= (m <= 2) ? 1 : 0;
		const auto era = (y >= 0 ? y : y - 399) / 400;
		const auto yoe = y - era * 400;
		const auto doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
		const auto doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
		return era * 146097 + doe - 719468;
	}
	[[nodiscard]] int dayNumber() const {
		return DaysFromCivil(year, month + 1, day);
	}
	[[nodiscard]] int season() const { // 0 winter, 1 spring, 2 summer, 3 autumn
		return (month == 11 || month < 2) ? 0 : (month < 5) ? 1 : (month < 8) ? 2 : 3;
	}
	// Sunrise and sunset in Saint Petersburg, minutes since the local midnight,
	// by the NOAA solar equations.
	void updateSunTimes() const {
		const auto today = dayNumber();
		if (sunTimesDay == today) {
			return;
		}
		sunTimesDay = today;
		const auto doy = today - DaysFromCivil(year, 1, 1) + 1;
		const auto g = 2. * kPi / 365. * (doy - 1);
		const auto equation = 229.18 * (.000075
			+ .001868 * std::cos(g)
			- .032077 * std::sin(g)
			- .014615 * std::cos(2. * g)
			- .040849 * std::sin(2. * g));
		const auto declination = .006918
			- .399912 * std::cos(g)
			+ .070257 * std::sin(g)
			- .006758 * std::cos(2. * g)
			+ .000907 * std::sin(2. * g)
			- .002697 * std::cos(3. * g)
			+ .00148 * std::sin(3. * g);
		const auto radians = kPi / 180.;
		const auto latitude = kSaintPetersburgLatitude * radians;
		const auto cosine = std::cos(90.833 * radians)
			/ (std::cos(latitude) * std::cos(declination))
			- std::tan(latitude) * std::tan(declination);
		const auto halfDay = std::acos(std::clamp(cosine, -1., 1.)) / radians;
		const auto noon = 720.
			- 4. * kSaintPetersburgLongitude
			- equation
			+ kSaintPetersburgUtcMinutes;
		sunriseMinutes = noon - 4. * halfDay;
		sunsetMinutes = noon + 4. * halfDay;
	}
	[[nodiscard]] double phase() const {
		if (mode == ZG_SKY_MODE_NIGHT) {
			return 1380.;
		} else if (mode == ZG_SKY_MODE_DAY) {
			return 780.;
		}
		updateSunTimes();
		const auto sunrise = sunriseMinutes;
		const auto sunset = sunsetMinutes;
		if (minutes >= sunrise && minutes <= sunset) {
			return 345. + (minutes - sunrise) / (sunset - sunrise) * 870.;
		}
		const auto nightLength = 1440. - (sunset - sunrise);
		const auto t = std::fmod(minutes - sunset + 1440., 1440.) / nightLength;
		return std::fmod(1215. + t * 570., 1440.);
	}
	[[nodiscard]] double moonAge() const {
		const auto jd = dayNumber() + minutes / 1440. + 2440587.5;
		auto p = std::fmod((jd - 2451550.1) / 29.530588853, 1.);
		return (p < 0.) ? (p + 1.) : p;
	}
	[[nodiscard]] Palette keyPalette(double ph) const {
		const auto &keys = KeyFrames();
		auto i = 0;
		while (i < int(keys.size()) - 2 && keys[i + 1].time <= ph) {
			++i;
		}
		const auto &a = keys[i];
		const auto &b = keys[i + 1];
		auto t = (ph - a.time) / double(b.time - a.time);
		t = t * t * (3. - 2. * t);
		auto result = Palette();
		for (auto j = 0; j != 8; ++j) {
			result.sky[j] = Mix(a.sky[j], b.sky[j], t);
		}
		for (auto j = 0; j != 4; ++j) {
			result.hill[j] = Mix(a.hill[j], b.hill[j], t);
		}
		result.cloud = Mix(a.cloud, b.cloud, t);
		result.cloudAlpha = a.cloudAlpha + (b.cloudAlpha - a.cloudAlpha) * t;
		result.star = a.star + (b.star - a.star) * t;
		return result;
	}
	[[nodiscard]] double starNow() const {
		return keyPalette(phase()).star;
	}
	[[nodiscard]] bool isNight() const {
		return starNow() > .4;
	}
	[[nodiscard]] bool isDay() const {
		const auto p = phase();
		return p > 420. && p < 1110.;
	}
	[[nodiscard]] bool isDusk() const {
		const auto p = phase();
		return p > 1190. && p < 1300.;
	}
	[[nodiscard]] bool isDawn() const {
		const auto p = phase();
		return p > 300. && p < 430.;
	}
	[[nodiscard]] bool isEvening() const {
		const auto p = phase();
		return p > 1080. && p < 1250.;
	}
	[[nodiscard]] bool isDate(int m, int d) const {
		return (month == m) && (day == d);
	}
	[[nodiscard]] bool halloween() const {
		return isDate(9, 31);
	}
	[[nodiscard]] int weatherNow() const {
		if (weatherSetting != ZG_SKY_WEATHER_AUTO) {
			return weatherSetting;
		}
		// The same weather for three hours, picked by the date and the hour.
		const auto block = dayNumber() * 8 + int(minutes) / 180;
		auto hash = uint32_t(block) * 2654435761U;
		hash ^= hash >> 13;
		const auto roll = int((hash % 1000U));
		const auto pick = [&](std::initializer_list<std::pair<int, int>> list) {
			auto sum = 0;
			for (const auto &[weather, share] : list) {
				sum += share;
				if (roll < sum) {
					return weather;
				}
			}
			return int(ZG_SKY_WEATHER_CLEAR);
		};
		switch (season()) {
		case 0: return pick({
			{ ZG_SKY_WEATHER_SNOW, 450 },
			{ ZG_SKY_WEATHER_BLIZZARD, 50 },
			{ ZG_SKY_WEATHER_FOG, 50 } });
		case 1: return pick({
			{ ZG_SKY_WEATHER_RAIN, 150 },
			{ ZG_SKY_WEATHER_STORM, 50 },
			{ ZG_SKY_WEATHER_WIND, 70 },
			{ ZG_SKY_WEATHER_FOG, 50 } });
		case 2: return pick({
			{ ZG_SKY_WEATHER_RAIN, 120 },
			{ ZG_SKY_WEATHER_STORM, 80 } });
		}
		return pick({
			{ ZG_SKY_WEATHER_RAIN, 200 },
			{ ZG_SKY_WEATHER_WIND, 100 },
			{ ZG_SKY_WEATHER_FOG, 120 } });
	}

	// ---------- geometry ----------
	void rebuild() {
		k = H / 128.;
		auto seed = uint32_t(11);
		const auto r = [&](int n) {
			seed = uint32_t((uint64_t(seed) * 16807ULL) % 2147483647ULL);
			return int(seed % uint32_t(std::max(n, 1)));
		};
		stars.clear();
		const auto starsCount = int(std::round(30. * (W / 192. + .2)));
		for (auto i = 0; i != starsCount; ++i) {
			stars.push_back({
				r(W),
				r(int(std::round(78. * k))),
				F() * 20.,
				6. + F() * 10.,
				i < 3 });
		}
		const auto columns = W / 3 + 2 + kHillMargin * 2;
		const double params[3][4] = {
			{ 98., 5., .045, 0. },
			{ 107., 5., .06, 2. },
			{ 116., 4., .05, 4. } };
		for (auto i = 0; i != 3; ++i) {
			auto &list = hills[i];
			list.resize(columns);
			const auto [base, a, f, p] = std::array<double, 4>{
				params[i][0], params[i][1], params[i][2], params[i][3] };
			for (auto q = 0; q != columns; ++q) {
				const auto x = double((q - kHillMargin) * 3);
				list[q] = int(std::floor(
					(base * k
						+ a * std::sin(x * f + p)
						+ a * .5 * std::sin(x * f * 2.3 + p)) / 2.)) * 2;
			}
		}
		windows.clear();
		for (auto i = 0; i != 14; ++i) {
			const auto x = r(W);
			windows.push_back({
				x,
				rawRidge(1, x) + 3 + r(4),
				1120 + r(130),
				(1350 + r(180)) % 1440 });
		}
		clouds = { { .1, .15, 24 }, { .45, .28, 32 }, { .78, .1, 20 }, { .3, .44, 28 } };
		city.clear();
		for (auto i = 0; i != 46; ++i) {
			const auto x = r(W);
			city.push_back({ x, rawRidge(0, x) + 1 + r(3), 1150 + r(90) });
		}
		flowers.clear();
		const uint32_t flowerColors[] = { 0xFF9BC8, 0xFFE14D, 0xFFFFFF, 0xC49BFF };
		for (auto i = 0; i != 50; ++i) {
			flowers.push_back({ r(W), 1 + r(2), 2 + r(6), flowerColors[r(4)] });
		}
		drops.clear();
		petals.clear();
		events.clear();
		delayed.clear();
		paletteAge = kPaletteInterval;
		fullRepaint = true;
	}
	[[nodiscard]] int rawRidge(int i, int x) const {
		const auto &list = hills[i];
		const auto q = std::clamp(
			x / 3 + kHillMargin,
			0,
			int(list.size()) - 1);
		return list[q];
	}
	[[nodiscard]] int ridge(int i, double x) const {
		return rawRidge(i, int(x) - hillOffsetX[i]) + hillOffsetY;
	}
	int lane() {
		return int(std::round(H * (chatOpen ? .17 : .06)))
			+ R(int(std::round(H * .26)));
	}

	// ---------- events ----------
	Ev *spawn(Id id, Ev e, bool multi = false) {
		if (!multi) {
			for (const auto &other : events) {
				if (other.id == id) {
					return nullptr;
				}
			}
		}
		e.id = id;
		e.t = 0.;
		events.push_back(std::move(e));
		return &events.back();
	}
	void later(double seconds, std::function<void()> callback) {
		delayed.push_back({ T + seconds, std::move(callback) });
	}
	void moving(Id id, const Frames &frames, const Pal &pal, Moving o) {
		const auto w = int(frames[0][0].size());
		const auto h = int(frames[0].size());
		auto e = Ev();
		e.layer = o.layer;
		e.rare = o.rare;
		e.px = (o.x != kNoValue)
			? o.x
			: (o.dir > 0) ? (-w - 2) : (W + 2);
		e.py = (o.y != kNoValue) ? o.y : lane();
		e.update = [=](Ev &ev, double dt) {
			ev.px += o.dir * o.speed * dt;
			ev.py += o.vy * dt;
			return (o.dir > 0)
				? (ev.px < W + o.tail + 2)
				: (ev.px > -w - o.tail - 2);
		};
		e.paint = [=, this](Ev &ev) {
			const auto &f = frames[size_t(ev.t * o.fps) % frames.size()];
			const auto X = int(std::round(ev.px));
			const auto Y = int(std::round(ev.py + std::sin(ev.t * 1.3) * o.bob));
			ev.bx = X;
			ev.by = Y;
			ev.bw = w;
			ev.bh = h;
			if (o.pre) {
				o.pre(ev, X, Y, o.dir);
			}
			if (o.alpha > 0.) {
				alpha = o.alpha;
			}
			sprite(f, X, Y, pal, o.dir < 0);
			alpha = 1.;
			if (o.post) {
				o.post(ev, X, Y, o.dir);
			}
		};
		spawn(id, std::move(e));
	}
	void burst(int x, int y, uint32_t color, int n, double life, double speed) {
		auto e = Ev();
		for (auto i = 0; i != n; ++i) {
			e.list.push_back({
				i / double(n) * 2. * kPi,
				speed * (.7 + F() * .5),
				0.,
				0. });
		}
		e.update = [=](Ev &ev, double) { return ev.t < life; };
		e.paint = [=, this](Ev &ev) {
			alpha = std::max(0., 1. - ev.t / life);
			for (const auto &q : ev.list) {
				const auto dd = q[1] * ev.t;
				put(
					int(std::round(x + std::cos(q[0]) * dd)),
					int(std::round(y + std::sin(q[0]) * dd + ev.t * ev.t * 7.)),
					C(color));
			}
			alpha = 1.;
		};
		spawn(Id::Burst, std::move(e), true);
	}
	void meteor(uint32_t c0 = 0xFFFFFF, uint32_t c1 = 0xD9CCFF, uint32_t c2 = 0x8F6CFF) {
		const auto mx = int(std::round(W * .45)) + R(int(std::round(W * .5)));
		const auto my = int(std::round(H * (chatOpen ? .16 : .05))) + R(20);
		auto e = Ev();
		e.update = [](Ev &ev, double) { return ev.t < .9; };
		e.paint = [=, this](Ev &ev) {
			const auto dd = ev.t * 70.;
			alpha = std::clamp((.9 - ev.t) / .25, 0., 1.);
			for (auto i = 0; i != 6; ++i) {
				rect(
					(i == 0) ? c0 : (i < 3) ? c1 : c2,
					int(std::round(mx - dd)) + i * 2,
					int(std::round(my + dd / 2.)) - i,
					2,
					1);
			}
			alpha = 1.;
		};
		spawn(Id::Meteor, std::move(e), true);
	}
	void flockPaint(
			const std::vector<std::array<int, 2>> &points,
			int X,
			int Y,
			uint32_t color,
			bool flap,
			int dir) {
		for (const auto &point : points) {
			const auto px = X - point[0] * dir;
			const auto py = Y + point[1];
			put(px, py, C(color));
			put(px - 1, py + (flap ? -1 : 1), C(color));
			put(px + 1, py + (flap ? -1 : 1), C(color));
		}
	}
	void flock(
			Id id,
			std::vector<std::array<int, 2>> points,
			int dir,
			double speed,
			uint32_t color,
			int y = kNoValue) {
		auto width = 0;
		for (const auto &point : points) {
			width = std::max(width, point[0]);
		}
		auto e = Ev();
		e.px = (dir > 0) ? -4. : (W + width + 4.);
		e.py = (y != kNoValue) ? y : lane();
		e.update = [=](Ev &ev, double dt) {
			ev.px += dir * speed * dt;
			return (dir > 0) ? (ev.px < W + width + 6) : (ev.px > -6.);
		};
		e.paint = [=, this](Ev &ev) {
			flockPaint(
				points,
				int(std::round(ev.px)),
				int(std::round(ev.py)),
				color,
				int(ev.t / .4) % 2 == 0,
				dir);
		};
		spawn(id, std::move(e));
	}
	[[nodiscard]] static std::vector<std::array<int, 2>> Vee() {
		auto result = std::vector<std::array<int, 2>>();
		for (auto i = 0; i != 9; ++i) {
			const auto q = (i + 1) / 2;
			result.push_back({ q * 5, ((i % 2) ? 1 : -1) * q * 2 });
		}
		return result;
	}
	struct Spot {
		bool visible = false;
		int x = 0;
		int y = 0;
		double q = 0.;
	};
	[[nodiscard]] Spot moonSpot() const {
		const auto ph = phase();
		if (ph < 1230. && ph > 330.) {
			return {};
		}
		const auto p = std::fmod(ph - 1230. + 1440., 1440.) / 540.;
		const auto q = std::sin(kPi * p);
		return {
			true,
			int(std::round(W * (.07 + .86 * p))) + skyOffsetX,
			int(std::round((96. - 62. * q) * k)),
			q };
	}
	[[nodiscard]] Spot sunSpot() const {
		const auto ph = phase();
		if (ph < 345. || ph > 1215.) {
			return {};
		}
		const auto p = (ph - 345.) / 870.;
		const auto q = std::sin(kPi * p);
		return {
			true,
			int(std::round(W * (.07 + .86 * p))) + skyOffsetX,
			int(std::round((102. - 68. * q) * k)),
			q };
	}
	void jet() {
		static const Pal day = {
			{ 'T', 0x7C4DFF }, { 'W', 0xFFFFFF }, { 'D', 0x2A3550 }, { 'C', 0x2A3550 },
			{ 'B', 0x7C4DFF }, { 'G', 0xC9D2E6 }, { 'K', 0xAEB8D0 }, { 'E', 0x6F7A96 } };
		static const Pal night = {
			{ 'T', 0x141438 }, { 'W', 0x1B1B48 }, { 'D', 0xFFD86B }, { 'C', 0x2A2A60 },
			{ 'B', 0x141438 }, { 'G', 0x10102E }, { 'K', 0x0E0E28 }, { 'E', 0x0A0A20 } };
		static const Frames frames = { kJet };
		const auto dark = isNight();
		auto o = Moving();
		o.speed = 6.;
		o.tail = 70;
		o.pre = [=, this](Ev&, int X, int Y, int) {
			if (dark) {
				return;
			}
			for (auto i = 1; i != 34; ++i) {
				alpha = (1. - i / 34.) * .75;
				rect(0xFFFFFF, X - i * 2, Y + 5, 2, 1);
				rect(0xFFFFFF, X - i * 2, Y + 7, 2, 1);
			}
			alpha = 1.;
		};
		o.post = [=, this](Ev &ev, int X, int Y, int) {
			if (dark && int(ev.t * 1.6) % 2 == 0) {
				rect(0xFF4D5E, X + 10, Y + 8, 1, 1);
				rect(0xFFFFFF, X, Y, 1, 1);
			}
		};
		moving(Id::Jet, frames, dark ? night : day, std::move(o));
	}
	void banner(std::u32string words, Id id = Id::Banner) {
		static const Pal day = {
			{ 'T', 0x7C4DFF }, { 'W', 0xFFFFFF }, { 'D', 0x2A3550 }, { 'C', 0x2A3550 },
			{ 'B', 0x7C4DFF }, { 'G', 0xC9D2E6 }, { 'K', 0xAEB8D0 }, { 'E', 0x6F7A96 } };
		static const Frames frames = { kJet };
		const auto width = int(words.size()) * 4 + 3;
		auto o = Moving();
		o.speed = 6.;
		o.tail = width + 14;
		o.pre = [=, this](Ev&, int X, int Y, int) {
			for (auto i = 0; i != 10; ++i) {
				rect(0xFFFFFF, X - 10 + i, Y + 5, 1, 1);
			}
			const auto bx = X - width - 10;
			rect(0xFFE14D, bx, Y + 1, width, 9);
			rect(0xE5484D, bx, Y + 1, width, 1);
			rect(0xE5484D, bx, Y + 9, width, 1);
			text(words, bx + 2, Y + 3, 0x1B1B48);
		};
		moving(id, frames, day, std::move(o));
	}
	void airship(
			Id id,
			std::u32string label,
			const Pal &pal,
			uint32_t ink,
			const char *rare) {
		static const Frames frames = { kAirship };
		auto o = Moving();
		o.speed = 3.;
		o.bob = 1.5;
		o.rare = rare;
		o.post = [=, this](Ev&, int X, int Y, int) {
			const auto tw = int(label.size()) * 4;
			text(label, X + (26 - tw) / 2 + 1, Y + 1, ink);
		};
		moving(id, frames, pal, std::move(o));
	}
	void ufo(bool withCow) {
		const auto tx = 40 + R(std::max(10, W - 90));
		const auto ty = int(std::round(H * .34)) + R(10);
		const auto stop = withCow ? 7. : 3.5;
		auto e = Ev();
		e.rare = withCow ? "НЛО крадёт корову" : "НЛО";
		e.px = -12.;
		e.py = ty - 10.;
		e.a = withCow ? 0. : -1.;
		e.update = [=](Ev &ev, double dt) {
			if (ev.t < 1.6) {
				const auto m = std::min(1., dt * 3.);
				ev.px += (tx - ev.px) * m;
				ev.py += (ty - ev.py) * m;
			} else if (ev.t > stop) {
				ev.px += dt * 150.;
				ev.py -= dt * 70.;
			}
			if (withCow && ev.t > 2. && ev.t < stop) {
				ev.a = std::min(1., (ev.t - 2.) / (stop - 2.4));
			}
			return ev.t < stop + 2.;
		};
		e.paint = [=, this](Ev &ev) {
			static const Pal cowPal = { { 'W', 0xFFFFFF }, { 'K', 0x22223A } };
			const auto X = int(std::round(ev.px));
			const auto Y = int(std::round(ev.py + std::sin(ev.t * 4.)));
			ev.bx = X;
			ev.by = Y;
			ev.bw = 9;
			ev.bh = 5;
			if (ev.t > 1.8 && ev.t < stop - .3) {
				const auto gy = ridge(2, X + 4) - Y - 5;
				alpha = .32;
				for (auto i = 0; i < gy; ++i) {
					const auto hw = 2 + i / 5;
					rect(0x9CFFB0, X + 4 - hw, Y + 5 + i, hw * 2 + 1, 1);
				}
				alpha = 1.;
			}
			if (withCow && ev.a >= 0. && ev.a < 1.) {
				const auto gy = ridge(2, tx + 4) - 5;
				sprite(kCow, tx, int(std::round(gy + (Y + 5 - gy) * ev.a)), cowPal);
			}
			const auto blink = int(ev.t * 6.) % 2;
			const Pal pal = {
				{ 'C', 0x9CFFB0 },
				{ 'S', 0xB8BFD6 },
				{ 'Y', blink ? 0xFFE14DU : 0xFF5A5AU } };
			sprite(kUfo, X, Y, pal);
		};
		spawn(withCow ? Id::Cow : Id::Ufo, std::move(e));
	}
	void fireworks(Id id, double duration, bool bigger) {
		auto e = Ev();
		e.a = 0.;
		e.update = [=, this](Ev &ev, double) {
			if (ev.t > ev.a && ev.t < duration) {
				ev.a = ev.t + .5 + F() * .6;
				const auto rx = 20 + R(W - 40);
				const auto top = int(std::round(H * .16)) + R(int(std::round(H * .25)));
				const uint32_t colors[] = {
					0xFF5A7A, 0xFFE14D, 0x6BE8FF, 0xB08BFF, 0x6BFF9E };
				const auto color = colors[R(5)];
				const auto y0 = int(std::round(H * .8));
				auto rise = Ev();
				rise.update = [=, this](Ev &r, double) {
					if (y0 - r.t * 70. <= top) {
						pendingEvents.push_back([=, this] {
							burst(
								rx,
								top,
								color,
								bigger ? 24 : 18,
								1.5,
								bigger ? 24. : 18.);
						});
						return false;
					}
					return true;
				};
				rise.paint = [=, this](Ev &r) {
					rect(color, rx, int(std::round(y0 - r.t * 70.)), 1, 2);
				};
				pendingEvents.push_back([this, rise = std::move(rise)]() mutable {
					spawn(Id::Rise, std::move(rise), true);
				});
			}
			return ev.t < duration + 2.;
		};
		e.paint = [](Ev&) {};
		spawn(id, std::move(e));
	}
	void startPetals(bool leaves, double seconds) {
		petalsAreLeaves = leaves;
		petalsLeft = seconds;
		petals.clear();
		const uint32_t leafColors[] = { 0xE2873A, 0xC65A28, 0xEDB64A, 0x9A4A22 };
		const uint32_t petalColors[] = { 0xFFC4DE, 0xFFD8E8, 0xFFAFD0 };
		const auto count = leaves ? 40 : 50;
		for (auto i = 0; i != count; ++i) {
			petals.push_back({
				F() * W,
				F() * H,
				F() * 6.,
				0.,
				leaves ? leafColors[R(4)] : petalColors[R(3)] });
		}
	}
	void simple(Id id, double life, int layer, std::function<void(Ev&)> paint, const char *rare = nullptr) {
		auto e = Ev();
		e.layer = layer;
		e.rare = rare;
		e.update = [=](Ev &ev, double) { return ev.t < life; };
		e.paint = std::move(paint);
		spawn(id, std::move(e));
	}

	void start(Id id) {
		switch (id) {
		case Id::Sent: {
			auto e = Ev();
			e.layer = 4;
			const auto sx = W * launchX;
			const auto sy = H * launchY;
			const auto dx = (launchX > .5 ? -.35 : 1.) * (W * .72 - sx * .3);
			e.update = [](Ev &ev, double) { return ev.t < 1.5; };
			e.paint = [=, this](Ev &ev) {
				static const Pal pal = {
					{ 'W', 0xFFFFFF }, { 'L', 0xA9B8F5 }, { 'D', 0x7F8FE0 } };
				const auto p = ev.t / 1.5;
				const auto q = 1. - std::pow(1. - p, 2.);
				alpha = std::clamp((1. - p) * 2.5, 0., 1.);
				for (auto i = 1; i != 7; ++i) {
					const auto w = std::max(0., q - i * .05);
					rect(
						0xFFFFFF,
						int(std::round(sx + dx * w)),
						int(std::round(sy - H * .75 * w)),
						1,
						1);
				}
				sprite(
					kPaper,
					int(std::round(sx + dx * q)),
					int(std::round(sy - H * .75 * q)),
					pal);
				alpha = 1.;
			};
			spawn(id, std::move(e), true);
		} break;
		case Id::Reaction: {
			const uint32_t colors[] = { 0xFF5A7A, 0xFFE14D, 0x6BE8FF };
			burst(
				int(std::round(W * (.55 + F() * .35))),
				int(std::round(H * (.3 + F() * .25))),
				colors[R(3)],
				16,
				1.2,
				16.);
		} break;
		case Id::Pigeon: {
			static const Pal pal = {
				{ 'G', 0xA7AEC6 }, { 'W', 0xFFFFFF }, { 'Y', 0xFFB347 }, { 'E', 0xF2E6C9 } };
			auto o = Moving();
			o.dir = -1;
			o.speed = 18.;
			o.fps = 7.;
			o.y = int(std::round(H * .3)) + R(14);
			moving(id, kPigeon, pal, std::move(o));
		} break;
		case Id::Ghost: {
			auto e = Ev();
			e.rare = "Призрак";
			e.px = int(std::round(W * .5)) + R(int(std::round(W * .35)));
			e.py = std::round(H * .35);
			e.update = [](Ev &ev, double dt) {
				ev.px -= dt * 1.5;
				return ev.t < 15.;
			};
			e.paint = [this](Ev &ev) {
				static const Pal pal = { { 'W', 0xE8ECFF }, { 'D', 0x2A2A60 } };
				const auto a = std::min(1., std::min(ev.t, 15. - ev.t) / 2.);
				const auto X = int(std::round(ev.px));
				const auto Y = int(std::round(ev.py + std::sin(ev.t * 1.6) * 3.));
				ev.bx = X;
				ev.by = Y;
				ev.bw = 6;
				ev.bh = 6;
				alpha = a * .72;
				sprite(kGhost, X, Y, pal);
				alpha = 1.;
			};
			spawn(id, std::move(e));
		} break;
		case Id::Deleted: {
			const auto tx = int(std::round(W * .35)) + R(int(std::round(W * .55)));
			const auto ty = ridge(2, tx);
			auto e = Ev();
			e.update = [=, this](Ev &ev, double) {
				if (ev.t >= 1. && ev.a == 0.) {
					ev.a = 1.;
					flash = .35;
					pendingEvents.push_back([=, this] {
						burst(tx, ty, 0xFF9A4D, 22, 1.1, 26.);
						burst(tx, ty, 0xFFE14D, 12, .8, 16.);
					});
				}
				return ev.t < 1.05;
			};
			e.paint = [=, this](Ev &ev) {
				const auto p = std::min(1., ev.t);
				const auto X = int(std::round(tx + 40. * (1. - p)));
				const auto Y = int(std::round(ty - 70. * (1. - p)));
				for (auto i = 0; i != 7; ++i) {
					rect(
						(i < 2) ? 0xFFFFFFU : (i < 4) ? 0xFFB347U : 0xE5484DU,
						X + i * 2,
						Y - i * 3,
						2,
						2);
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::Congrats: {
			meteor(0xFFFFFF, 0xFFE14D, 0xFFB347);
			burst(
				int(std::round(W * .7)),
				int(std::round(H * .3)),
				0xFFE14D,
				14,
				1.4,
				14.);
		} break;
		case Id::Banana: {
			const auto sx = W * launchX;
			const auto sy = H * launchY;
			const auto side = (launchX > .5) ? -.5 : 1.;
			auto e = Ev();
			e.layer = 4;
			e.update = [](Ev &ev, double) { return ev.t < 1.9; };
			e.paint = [=, this](Ev &ev) {
				const auto p = ev.t / 1.9;
				const auto q = p * p;
				const auto X = int(std::round(sx + W * .55 * q * side));
				const auto Y = int(std::round(sy - H * .95 * q));
				const Pal pal = {
					{ 'Y', 0xFFE14D },
					{ 'F', (int(ev.t * 12.) % 2) ? 0xFF7A3DU : 0xFFD86BU } };
				sprite(kBanana, X, Y, pal);
				for (auto i = 1; i != 6; ++i) {
					alpha = (1. - i / 6.) * .6;
					rect(0xC9D2E6, X - i * 2, Y + 7 + i * 2, 1, 1);
				}
				alpha = 1.;
			};
			spawn(id, std::move(e));
		} break;
		case Id::Meteor: meteor(); break;
		case Id::Shower: {
			auto e = Ev();
			e.update = [this](Ev &ev, double) {
				if (ev.t > ev.a * .45 && ev.a < 16.) {
					ev.a += 1.;
					pendingEvents.push_back([this] { meteor(); });
				}
				return ev.t < 9.;
			};
			e.paint = [](Ev&) {};
			spawn(id, std::move(e));
		} break;
		case Id::Comet: {
			auto e = Ev();
			e.rare = "Комета";
			e.px = W + 25.;
			e.py = std::round(H * .1) + R(14);
			e.update = [](Ev &ev, double dt) {
				ev.px -= dt * 5.;
				ev.py += dt * .5;
				return ev.px > -30.;
			};
			e.paint = [this](Ev &ev) {
				const auto X = int(std::round(ev.px));
				const auto Y = int(std::round(ev.py));
				ev.bx = X - 2;
				ev.by = Y - 2;
				ev.bw = 26;
				ev.bh = 6;
				for (auto i = 22; i > 0; --i) {
					alpha = (1. - i / 22.) * .85;
					rect(
						(i < 8) ? 0xE6DBFFU : 0x7FD4FFU,
						X + i,
						Y - int(std::round(i * .1)),
						1,
						1 + ((i > 4 && i < 14) ? 1 : 0));
				}
				alpha = 1.;
				rect(0xFFFFFF, X - 1, Y - 1, 2, 2);
			};
			spawn(id, std::move(e));
		} break;
		case Id::Satellite: {
			static const Frames frames = { kSatellite };
			static const Pal pal = {
				{ 'A', 0xC9D2E6 }, { 'P', 0x2F5FD8 }, { 'p', 0x7FA8FF }, { '=', 0xAEB8D0 },
				{ 'B', 0xE8C25A }, { 'S', 0xD9B24A }, { 'd', 0x6F7A96 } };
			auto o = Moving();
			o.speed = 5.;
			o.vy = -.25;
			o.post = [this](Ev &ev, int X, int Y, int) {
				if (int(ev.t * 1.2) % 3 == 0) {
					rect(0xFFFFFF, X + 9, Y - 1, 1, 1);
				}
			};
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::Chain: {
			auto e = Ev();
			e.px = -2.;
			e.py = lane();
			e.update = [this](Ev &ev, double dt) {
				ev.px += dt * 6.;
				return ev.px - 70. < W;
			};
			e.paint = [this](Ev &ev) {
				for (auto i = 0; i != 14; ++i) {
					put(
						int(std::round(ev.px)) - i * 5,
						int(std::round(ev.py + i * .9)),
						C(0xF4F0FF));
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::Ufo: ufo(false); break;
		case Id::Cow: ufo(true); break;
		case Id::Aurora: simple(id, 30., 0, [this](Ev &ev) {
			const auto a = std::min(1., std::min(ev.t, 30. - ev.t) / 5.);
			for (auto cx = 0; cx < W; cx += 2) {
				const auto y0 = 6. + 6. * std::sin(cx * .05 + T * .5);
				const auto hh = 20. + 9. * std::sin(cx * .03 + T * .35);
				const auto wave = std::sin(cx * .09 + T * .8);
				alpha = a * (.28 + .14 * wave);
				rect(0x4DFFB0, cx, int(std::round(y0)), 2, int(std::round(hh)));
				alpha = a * .22;
				rect(0xB06BFF, cx, int(std::round(y0 + hh)), 2, 9);
			}
			alpha = 1.;
		}); break;
		case Id::Flies: {
			auto e = Ev();
			e.layer = 3;
			for (auto i = 0; i != 14; ++i) {
				e.list.push_back({ F() * W, H * .72 + F() * H * .22, F() * 6., 0. });
			}
			e.update = [](Ev &ev, double dt) {
				for (auto &o : ev.list) {
					o[0] += std::sin(ev.t * .8 + o[2]) * dt * 2.;
					o[1] += std::cos(ev.t * .6 + o[2]) * dt * 1.5;
				}
				return ev.t < 35.;
			};
			e.paint = [this](Ev &ev) {
				const auto a = std::min(1., std::min(ev.t, 35. - ev.t) / 4.);
				for (const auto &o : ev.list) {
					alpha = a * std::max(0., std::sin(ev.t * 1.4 + o[2]));
					if (alpha > 0.) {
						put(int(std::round(o[0])), int(std::round(o[1])), C(0xD9FF6B));
					}
				}
				alpha = 1.;
			};
			spawn(id, std::move(e));
		} break;
		case Id::Bats: {
			auto e = Ev();
			e.px = -6.;
			e.py = std::round(H * .3);
			e.update = [this](Ev &ev, double dt) {
				ev.px += dt * 16.;
				return ev.px < W + 24;
			};
			e.paint = [this](Ev &ev) {
				const auto up = int(ev.t * 7.) % 2 == 0;
				const int offsets[3][2] = { { 0, 0 }, { 9, 6 }, { 17, -4 } };
				for (auto i = 0; i != 3; ++i) {
					const auto px = int(std::round(ev.px)) - offsets[i][0];
					const auto py = int(std::round(
						ev.py + offsets[i][1] + std::sin(ev.t * 5. + i * 2) * 5.));
					rect(0x120E2E, px, py, 1, 1);
					rect(0x120E2E, px - 2, py + (up ? -1 : 0), 2, 1);
					rect(0x120E2E, px + 1, py + (up ? -1 : 0), 2, 1);
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::Owl: {
			static const Pal pal = {
				{ 'W', 0x8C7A5A }, { 'B', 0xC9B48A }, { 'T', 0x6A5A40 } };
			const auto moon = moonSpot();
			auto o = Moving();
			o.dir = -1;
			o.speed = 10.;
			o.fps = 5.;
			o.y = moon.visible ? std::max(6, moon.y - 2) : lane();
			moving(id, kOwl, pal, std::move(o));
		} break;
		case Id::Wolf: {
			forceFull = 25.;
			auto e = Ev();
			e.layer = 2;
			e.rare = "Волк";
			e.px = int(std::round(W * .15)) + R(int(std::round(W * .55)));
			e.update = [](Ev &ev, double) { return ev.t < 25.; };
			e.paint = [this](Ev &ev) {
				static const Pal pal = { { 'K', 0x0A0A24 } };
				const auto X = int(ev.px);
				const auto Y = ridge(2, X + 3) - 6;
				ev.bx = X;
				ev.by = Y;
				ev.bw = 8;
				ev.bh = 6;
				sprite(kWolf[int(ev.t / 3.) % 2], X, Y, pal);
			};
			spawn(id, std::move(e));
		} break;
		case Id::Constellation: {
			const auto ox = int(std::round(W * .3)) + R(int(std::round(W * .4)));
			const auto oy = int(std::round(H * .14)) + R(10);
			simple(id, 25., 0, [=, this](Ev &ev) {
				static const int points[7][2] = {
					{ 0, 8 }, { 9, 6 }, { 17, 8 }, { 25, 11 },
					{ 32, 16 }, { 29, 24 }, { 20, 23 } };
				const auto a = std::min(1., std::min(ev.t, 25. - ev.t) / 3.);
				const auto n = std::min(6, int(ev.t / 1.2));
				alpha = a * .55;
				for (auto i = 0; i != n; ++i) {
					const auto ax = points[i][0], ay = points[i][1];
					const auto bx = points[i + 1][0], by = points[i + 1][1];
					const auto st = std::max(std::abs(bx - ax), std::abs(by - ay));
					for (auto s = 0; s < st; s += 2) {
						put(
							ox + int(std::round(ax + (bx - ax) * s / double(st))),
							oy + int(std::round(ay + (by - ay) * s / double(st))),
							C(0xB9A8FF));
					}
				}
				alpha = a;
				for (const auto &point : points) {
					rect(0xFFFFFF, ox + point[0], oy + point[1], 2, 2);
				}
				alpha = 1.;
			});
		} break;
		case Id::Rocket: {
			const auto rx = int(std::round(W * .2)) + R(int(std::round(W * .6)));
			const auto y0 = ridge(2, rx) - 7;
			simple(id, 7., 0, [=, this](Ev &ev) {
				static const Pal pal = {
					{ 'W', 0xFFFFFF }, { 'R', 0xE5484D }, { 'B', 0x3C6FE0 } };
				static const Pal stage = { { 'W', 0xAEB8D0 } };
				const auto e = ev.t * ev.t * 1.6;
				const auto Y = int(std::round(y0 - e * (H / 70.)));
				if (ev.t > 3.4 && ev.a == 0.) {
					ev.a = Y;
				}
				if (Y > -10) {
					for (auto i = 0; i < std::min(30., e * 1.5); ++i) {
						alpha = (1. - i / 30.) * .5;
						rect(0xD5D9E8, rx + 2 + (i % 3 - 1), Y + 8 + i * 2, 1, 1);
					}
					alpha = 1.;
					rect((int(ev.t * 12.) % 2) ? 0xFFB347U : 0xFF6A3DU, rx + 1, Y + 7, 3, 2);
					sprite(ev.a != 0. ? kRocketTop : kRocket, rx, Y, pal);
				}
				if (ev.a != 0.) {
					const auto dd = (ev.t - 3.4) * (ev.t - 3.4) * 5.;
					sprite(kRocketStage, rx - 1, int(std::round(ev.a + 6. + dd)), stage);
				}
			});
		} break;
		case Id::Whale: {
			static const Frames frames = { kWhale };
			static const Pal pal = {
				{ 'B', 0x3E58C8 }, { 'L', 0xA9C4F5 }, { 'W', 0xFFFFFF }, { 'T', 0x2E449E } };
			auto o = Moving();
			o.speed = 2.5;
			o.bob = 2.;
			o.rare = "Кит";
			o.alpha = .9;
			o.y = int(std::round(H * .2)) + R(8);
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::Ship: {
			static const Frames frames = { kShip };
			static const Pal pal = {
				{ 'S', 0xBFFFE0 }, { 'M', 0x8AD9B8 }, { 'H', 0x3F8F76 } };
			auto o = Moving();
			o.speed = 3.;
			o.bob = 1.5;
			o.rare = "Летучий голландец";
			o.alpha = .72;
			o.y = int(std::round(H * .2)) + R(10);
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::CatMoon: simple(id, 40., 0, [this](Ev &ev) {
			static const Pal pal = { { 'K', 0x16162E }, { 'G', 0xFFE14D } };
			const auto moon = moonSpot();
			if (!moon.visible) {
				ev.bw = 0;
				return;
			}
			const auto X = moon.x - 2;
			const auto Y = moon.y - 11;
			ev.bx = X;
			ev.by = Y;
			ev.bw = 5;
			ev.bh = 6;
			sprite(kCat, X, Y, pal);
			const auto swing = int(std::round(std::sin(ev.t * 2.) * 2.));
			rect(0x16162E, X + 5, Y + 5, 1, 1);
			rect(0x16162E, X + 6 + swing, Y + 6, 1, 3);
		}, "Кот на луне"); break;
		case Id::Lunar: {
			forceFull = 34.;
			auto e = Ev();
			e.update = [this](Ev &ev, double) {
				lunarRed = std::min(1., ev.t / 8.)
					* ((ev.t > 26.) ? std::max(0., (32. - ev.t) / 6.) : 1.);
				if (ev.t >= 32.) {
					lunarRed = 0.;
					return false;
				}
				return true;
			};
			e.paint = [](Ev&) {};
			spawn(id, std::move(e));
		} break;
		case Id::Camp: {
			const auto px = int(std::round(W * .2)) + R(int(std::round(W * .6)));
			simple(id, 60., 2, [=, this](Ev &ev) {
				static const Pal pal = { { 'O', 0xD6743A }, { 'K', 0x3A1E12 } };
				const auto X = px;
				const auto Y = ridge(2, X + 4) - 5;
				sprite(kTent, X, Y, pal);
				const auto fl = int(ev.t * 8.) % 3;
				rect(0xFFB347, X + 12, Y + 3 - (fl == 0 ? 1 : 0), 2, 2);
				rect(0xFF6A3D, X + 12, Y + 4, 3, 1);
				rect(0x5A3A22, X + 11, Y + 5, 5, 1);
				for (auto i = 0; i != 6; ++i) {
					alpha = (1. - i / 6.) * .45;
					rect(
						0xC9D2E6,
						X + 13 + int(std::round(std::sin(T * 1.2 + i) * 1.5)),
						Y + 1 - i * 2,
						1,
						1);
				}
				alpha = 1.;
			});
		} break;
		case Id::Train: {
			auto e = Ev();
			e.layer = 1;
			e.px = -4.;
			e.update = [this](Ev &ev, double dt) {
				ev.px += dt * 14.;
				return ev.px - 70. < W;
			};
			e.paint = [this](Ev &ev) {
				const auto night = starNow() > .3;
				const auto X = int(std::round(ev.px));
				for (auto i = 0; i != 5; ++i) {
					const auto cx = X - i * 14;
					if (cx > W || cx < -14) {
						continue;
					}
					const auto y = ridge(1, cx + 5) - 5;
					rect((i == 0) ? 0x3A3A52U : 0x5A4E8CU, cx, y, 12, 4);
					rect(0x16162E, cx + 1, y + 4, 2, 1);
					rect(0x16162E, cx + 8, y + 4, 2, 1);
					if (i == 0) {
						rect(0x3A3A52, cx + 7, y - 2, 2, 2);
						if (night) {
							rect(0xFFF3B0, cx + 12, y + 1, 2, 1);
						}
						for (auto q = 0; q != 4; ++q) {
							alpha = (1. - q / 4.) * .5;
							rect(0xD5D9E8, cx + 7 - q * 2, y - 3 - q, 2, 1);
						}
						alpha = 1.;
					} else {
						for (auto q = 0; q != 3; ++q) {
							rect(night ? 0xFFD86BU : 0xC9D2E6U, cx + 2 + q * 3, y + 1, 2, 1);
						}
					}
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::Jet: jet(); break;
		case Id::Banner: banner(U"ZALUPAGRAM"); break;
		case Id::Birds:
			flock(id, { { 0, 0 }, { 7, 3 }, { 13, -2 }, { 20, 2 }, { 26, -1 } }, 1, 8., 0x22304F);
			break;
		case Id::Balloon:
		case Id::CatBalloon: {
			static const Frames plain = { kBalloon };
			static const Frames cat = { kCatBalloon };
			static const Pal pal = {
				{ 'R', 0xE5484D }, { 'W', 0xFFE9C9 }, { 'B', 0x5A3A22 },
				{ 'T', 0x8A5A32 }, { 'K', 0x2A2A40 } };
			auto o = Moving();
			o.speed = 2.6;
			o.vy = -.35;
			o.bob = 1.5;
			o.y = int(std::round(H * .3)) + R(10);
			if (id == Id::CatBalloon) {
				o.rare = "Кот на шаре";
			}
			moving(id, (id == Id::CatBalloon) ? cat : plain, pal, std::move(o));
		} break;
		case Id::Airship: {
			static const Pal pal = {
				{ 'F', 0x6A7088 }, { 'S', 0xAEB8D0 }, { 'G', 0x5A6078 }, { 'D', 0xFFE9A0 } };
			airship(id, U"ZALUPAGRAM", pal, 0x1B1B48, nullptr);
		} break;
		case Id::Legion: {
			static const Pal pal = {
				{ 'F', 0x7A1E22 }, { 'S', 0x2F3A2A }, { 'G', 0x1A1F18 }, { 'D', 0xFFD86B } };
			airship(id, U"ЛЕГИОН", pal, 0xFFE14D, "Дирижабль Легион");
		} break;
		case Id::Helicopter: {
			static const Pal pal = {
				{ 'R', 0x3A3A52 }, { 'M', 0x3A3A52 }, { 'T', 0x2E449E }, { 'Y', 0xFFFFFF },
				{ 'B', 0x3C6FE0 }, { 'W', 0xBFE3FF }, { 'G', 0x3A3A52 } };
			auto o = Moving();
			o.speed = 9.;
			o.fps = 10.;
			o.bob = 1.;
			moving(id, kHelicopter, pal, std::move(o));
		} break;
		case Id::Parachute: {
			const auto px = int(std::round(W * .2)) + R(int(std::round(W * .55)));
			auto e = Ev();
			e.py = std::round(H * .12);
			e.update = [=, this](Ev &ev, double dt) {
				ev.py += ((ev.t < 1.2) ? 26. : 5.) * dt;
				return ev.py + 11. < ridge(2, px + 5);
			};
			e.paint = [=, this](Ev &ev) {
				static const Pal pal = {
					{ 'R', 0xE5484D }, { 'W', 0xFFF3DC }, { 'L', 0xE8ECF6 }, { 'P', 0x2A2A40 } };
				const auto Y = int(std::round(ev.py));
				const auto X = px + int(std::round(std::sin(ev.t * .9) * 2.));
				if (ev.t < 1.2) {
					rect(0x7A5A3A, X + 5, Y + 7, 1, 2);
					rect(0xE5484D, X + 4, Y + 6, 3, 1);
				} else {
					sprite(kCanopy, X, Y, pal);
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::Kite: {
			const auto px = int(std::round(W * .25)) + R(int(std::round(W * .5)));
			const auto py = int(std::round(H * .28)) + R(10);
			simple(id, 40., 0, [=, this](Ev &ev) {
				static const Pal pal = { { 'R', 0xE5484D }, { 'Y', 0xFFE14D } };
				const auto X = px + int(std::round(std::sin(ev.t * .7) * 5.));
				const auto Y = py + int(std::round(std::cos(ev.t * .9) * 3.));
				const auto gx = px - 20;
				const auto gy = ridge(2, gx) - 1;
				const auto st = std::abs(gy - Y);
				alpha = .7;
				for (auto i = 0; i < st; i += 2) {
					put(
						int(std::round(gx + (X + 3 - gx) * i / double(st))),
						gy - i,
						C(0xFFFFFF));
				}
				alpha = 1.;
				sprite(kKite, X, Y, pal);
				for (auto i = 1; i != 6; ++i) {
					put(
						X + 3 + int(std::round(std::sin(ev.t * 3. + i) * 1.5)),
						Y + 6 + i * 2,
						C((i % 2) ? 0x6BE8FF : 0xFF9BC8));
				}
				rect(0x2A2A40, gx, gy - 3, 2, 3);
			});
		} break;
		case Id::Sheep: startSheep(false); break;
		case Id::Flash: {
			flash = 1.;
			startSheep(true);
			later(.06, [this] {
				const auto cx = int(std::round(W * .5));
				burst(cx, ridge(2, cx), 0xFF9A4D, 26, 1.3, 30.);
			});
		} break;
		case Id::Rooster: {
			const auto px = int(std::round(W * .15)) + R(int(std::round(W * .6)));
			simple(id, 14., 2, [=, this](Ev &ev) {
				static const Pal pal = {
					{ 'R', 0xE5484D }, { 'W', 0xF4E8CC }, { 'Y', 0xFFB347 },
					{ 'T', 0x3A2E5A }, { 'L', 0xFFB347 } };
				sprite(kRooster[int(ev.t / 1.5) % 2], px, ridge(2, px + 3) - 7, pal);
			});
		} break;
		case Id::FogLow: simple(id, 40., 3, [this](Ev &ev) {
			const auto a = std::min(1., std::min(ev.t, 40. - ev.t) / 6.);
			alpha = a * .28;
			for (auto i = 0; i != 6; ++i) {
				const auto oy = int(std::round(H * .66)) + i * 6;
				const auto off = int(std::round(std::sin(T * .15 + i) * 14.));
				rect(0xF3EEF8, off - 16, oy, W + 32, 5);
			}
			alpha = 1.;
		}); break;
		case Id::Solar: {
			auto e = Ev();
			e.update = [this](Ev &ev, double) {
				solarCover = std::max(0., 1. - std::abs(ev.t / 30. - .5) * 2.6);
				if (ev.t >= 30.) {
					solarCover = 0.;
					return false;
				}
				return true;
			};
			e.paint = [this](Ev &ev) {
				const auto sun = sunSpot();
				if (!sun.visible) {
					return;
				}
				disc(
					C(0x0B0F2E),
					int(std::round(sun.x + (1. - 2. * ev.t / 30.) * 16.)),
					sun.y,
					6);
				if (solarCover > .8) {
					alpha = .5;
					for (auto a = 0; a != 16; ++a) {
						put(
							int(std::round(sun.x + std::cos(a * .4) * 8.)),
							int(std::round(sun.y + std::sin(a * .4) * 8.)),
							C(0xFFF7C2));
					}
					alpha = 1.;
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::RedMoon: {
			const auto px = int(std::round(W * .7));
			simple(id, 45., 0, [=, this](Ev &ev) {
				const auto a = std::min(1., std::min(ev.t, 45. - ev.t) / 5.);
				const auto Y = int(std::round(H * .72 - ev.t * .3));
				alpha = a * .25;
				disc(C(0xFFB07A), px, Y, 11);
				alpha = a;
				disc(C(0xF07A3D), px, Y, 9);
				rect(0xD65F2E, px - 3, Y - 3, 3, 2);
				rect(0xD65F2E, px + 2, Y + 2, 3, 2);
				rect(0xD65F2E, px - 4, Y + 3, 2, 1);
				alpha = 1.;
			});
		} break;
		case Id::Home:
			flock(
				id,
				{ { 0, 0 }, { 5, 2 }, { 10, -1 }, { 15, 3 }, { 19, 0 }, { 24, 2 }, { 28, -2 } },
				-1,
				7.,
				0x1E1436,
				int(std::round(H * .3)));
			break;
		case Id::Cranes: flock(id, Vee(), 1, 7., 0x3A3A52); break;
		case Id::Geese: flock(id, Vee(), -1, 7., 0x2A2A40); break;
		case Id::Petals: startPetals(false, 30.); break;
		case Id::Leaves: startPetals(true, 30.); break;
		case Id::Hearts: {
			auto e = Ev();
			for (auto i = 0; i != 12; ++i) {
				e.list.push_back({
					double(8 + R(std::max(10, W - 20))),
					i * 1.6 + F(),
					6. + F() * 4.,
					0. });
			}
			e.update = [](Ev &ev, double) { return ev.t < 28.; };
			e.paint = [this](Ev &ev) {
				static const Pal pal = { { 'R', 0xFF5A8C } };
				for (const auto &o : ev.list) {
					const auto t = ev.t - o[1];
					if (t < 0.) {
						continue;
					}
					const auto Y = int(std::round(H * .95 - t * o[2]));
					const auto X = int(std::round(o[0] + std::sin(t) * 2.));
					if (Y >= -8) {
						sprite(kHeart, X, Y, pal);
						rect(0xFFFFFF, X + 3, Y + 6, 1, 3);
					}
				}
			};
			spawn(id, std::move(e));
		} break;
		case Id::AprilFirst: {
			flipUntil = T + 60.;
			ufo(false);
			later(15., [this] { ufo(false); });
		} break;
		case Id::AprilTwelfth: {
			start(Id::Rocket);
			later(3., [this] { start(Id::Satellite); });
			later(9., [this] { start(Id::Chain); });
		} break;
		case Id::Witch: {
			static const Frames frames = { kWitch };
			static const Pal pal = {
				{ 'H', 0x2A1A4A }, { 'K', 0xFFDFB0 }, { 'B', 0x5A3A22 }, { 'T', 0x5A3A22 } };
			auto o = Moving();
			o.speed = 13.;
			o.bob = 3.;
			o.y = int(std::round(H * .24));
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::ZgBirthday: {
			banner(U"ZALUPAGRAM", Id::ZgBirthday);
			fireworks(Id::Fireworks, 10., false);
			start(Id::Hearts);
		} break;
		case Id::MyBirthday: {
			banner(U"С ДР", Id::MyBirthday);
			fireworks(Id::Fireworks, 10., true);
		} break;
		case Id::NewYear: {
			fireworks(Id::NewYear, 14., true);
			start(Id::Santa);
		} break;
		case Id::Santa: {
			static const Frames frames = { kSanta };
			static const Pal pal = {
				{ 'R', 0xE5484D }, { 'W', 0xFFFFFF }, { 'G', 0x8A5A32 }, { 'B', 0x6A4A2E } };
			auto o = Moving();
			o.dir = -1;
			o.speed = 15.;
			o.bob = 2.;
			o.rare = "Дед Мороз";
			o.y = int(std::round(H * .2));
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::Dino: {
			const auto px = int(std::round(W * .15)) + R(int(std::round(W * .65)));
			simple(id, 6., 1, [=, this](Ev &ev) {
				static const Pal pal = {
					{ 'G', 0x3C8F4F }, { 'K', 0x16162E }, { 'W', 0xFFFFFF } };
				const auto up = std::min(1., std::min(ev.t, 6. - ev.t));
				const auto Y = ridge(2, px + 5) - int(std::round(up * 7.));
				ev.bx = px;
				ev.by = Y;
				ev.bw = 10;
				ev.bh = 8;
				sprite(kDino, px, Y, pal);
			}, "Динозавр");
		} break;
		case Id::Hero: {
			static const Frames frames = { kHero };
			static const Pal pal = {
				{ 'C', 0xE5484D }, { 'B', 0x2F5FD8 }, { 'S', 0xFFDFB0 }, { 'R', 0x2A2A40 } };
			auto o = Moving();
			o.speed = 32.;
			o.rare = "Супергерой";
			moving(id, frames, pal, std::move(o));
		} break;
		case Id::Skier: {
			auto e = Ev();
			e.layer = 2;
			e.rare = "Лыжник";
			e.px = std::round(W * .2);
			e.update = [this](Ev &ev, double dt) {
				ev.px += dt * 22.;
				return ev.px < W + 6;
			};
			e.paint = [this](Ev &ev) {
				static const Pal pal = {
					{ 'R', 0xE5484D }, { 'K', 0x2A2A40 }, { 'S', 0x3A3A52 } };
				const auto X = int(std::round(ev.px));
				const auto Y = ridge(2, X + 2) - 5;
				ev.bx = X;
				ev.by = Y;
				ev.bw = 4;
				ev.bh = 5;
				for (auto i = 1; i != 14; ++i) {
					alpha = (1. - i / 14.) * .6;
					rect(0xFFFFFF, X - i * 2, ridge(2, X - i * 2) - 1, 2, 1);
				}
				alpha = 1.;
				sprite(kSkier, X, Y, pal);
			};
			spawn(id, std::move(e));
		} break;
		case Id::Rainbow: simple(id, 22., 0, [this](Ev &ev) {
			const uint32_t colors[] = {
				0xFF5A5A, 0xFF9E3D, 0xFFE14D, 0x57D163, 0x4DA3FF, 0x8F6CFF };
			const auto cx = W * .61;
			const auto cy = H * .875;
			alpha = std::min(1., std::min(ev.t, 22. - ev.t) / 4.) * .75;
			for (auto i = 0; i != 6; ++i) {
				const auto r = (W * .34) - i * 2;
				for (auto a = 180.; a <= 360.; a += .7) {
					const auto rad = a * kPi / 180.;
					rect(
						colors[i],
						int(std::round(cx + r * std::cos(rad))),
						int(std::round(cy + r * std::sin(rad))),
						1,
						2);
				}
			}
			alpha = 1.;
		}); break;
		case Id::Burst:
		case Id::Rise:
		case Id::Fireworks:
			break;
		}
	}
	void startSheep(bool run) {
		auto e = Ev();
		e.layer = 2;
		for (auto i = 0; i != 6; ++i) {
			e.list.push_back({
				double(int(std::round(W * .15)) + R(int(std::round(W * .65)))),
				R(2) ? 1. : -1.,
				F() * 5.,
				0. });
		}
		e.update = [=, this](Ev &ev, double dt) {
			for (auto &o : ev.list) {
				if (run) {
					o[0] += o[1] * 30. * dt;
				} else if (std::sin(ev.t * .6 + o[2]) > .4) {
					o[0] += o[1] * 2.2 * dt;
					if (o[0] < 3. || o[0] > W - 8.) {
						o[1] = -o[1];
					}
				}
			}
			return ev.t < (run ? 5. : 60.);
		};
		e.paint = [=, this](Ev &ev) {
			static const Pal pal = { { 'W', 0xF4F2EA }, { 'K', 0x22223A } };
			for (const auto &o : ev.list) {
				if (o[0] < -8. || o[0] > W + 2.) {
					continue;
				}
				const auto X = int(std::round(o[0]));
				const auto Y = ridge(2, X + 2) - 4;
				const auto frame = run
					? int(ev.t * 8.) % 2
					: int(ev.t * 1.5 + o[2]) % 2;
				sprite(kSheep[frame], X, Y, pal, o[1] < 0.);
			}
		};
		spawn(Id::Sheep, std::move(e));
	}
	void setupAutomatic() {
		// Means are divided by eventRate, 2 by default. Out of its time an event
		// is `rarer` times less likely, but it can always happen.
		const auto add = [&](
				Id id,
				double mean,
				std::function<bool()> favorable,
				double rarer = 20.) {
			automatic.push_back({
				id,
				mean,
				mean * rarer,
				std::move(favorable) });
		};
		// A holiday out of its date: about 20 hours of the sky on screen.
		const auto holiday = [&](
				Id id,
				double mean,
				std::function<bool()> favorable) {
			automatic.push_back({
				id,
				mean,
				kHolidayOtherMean,
				std::move(favorable) });
		};
		const auto always = [] { return true; };
		const auto night = [this] { return isNight(); };
		const auto dayTime = [this] { return isDay(); };
		const auto moonVisible = [this] { return moonSpot().visible; };
		const auto sunVisible = [this] { return sunSpot().visible; };

		// Often, at their time of day.
		add(Id::Meteor, 90., night);
		add(Id::Birds, 180., dayTime);
		add(Id::Satellite, 300., night);
		add(Id::Jet, 240., dayTime, 2.);
		add(Id::Helicopter, 900., dayTime);
		add(Id::Balloon, 1200., dayTime);
		add(Id::Owl, 1200., night);
		add(Id::Train, 1800., night);
		add(Id::Comet, 1800., night);
		add(Id::Banner, 1800., dayTime);
		add(Id::Parachute, 1800., dayTime);
		add(Id::Chain, 2400., night);
		add(Id::Kite, 2400., dayTime);
		add(Id::Constellation, 3600., night);
		add(Id::Ufo, 3600., night);
		add(Id::Airship, 3600., dayTime);
		add(Id::Rocket, 7200., night);
		add(Id::Whale, 10800., night);

		// At dawn and dusk.
		add(Id::Rooster, 1200., [this] { return isDawn(); });
		add(Id::FogLow, 1800., [this] { return isDawn(); });
		add(Id::Home, 600., [this] { return isEvening(); });
		add(Id::RedMoon, 7200., [this] { return isEvening(); });
		add(Id::Bats, 600., [this] { return isDusk(); });
		add(Id::Camp, 7200., [this] { return isDusk(); });

		// By the season or the moon.
		add(Id::Flies, 3600., [this] { return isNight() && season() == 2; });
		add(Id::Aurora, 5400., [this] { return isNight() && season() == 0; });
		add(Id::Shower, 3600., [this] {
			return isNight() && (month == 7 || month == 11);
		});
		add(Id::Wolf, 1800., [this] {
			return isNight() && std::abs(moonAge() - .5) < .04;
		});
		add(Id::Sheep, 1800., [this] { return isDay() && season() != 0; });
		add(Id::Skier, 1800., [this] { return season() == 0 && isDay(); });
		add(Id::Cranes, 2400., [this] { return season() == 1 && isDay(); });
		add(Id::Petals, 2400., [this] { return season() == 1 && isDay(); });
		add(Id::Leaves, 1800., [this] { return season() == 3 && isDay(); });
		add(Id::Geese, 2400., [this] { return season() == 3 && isDay(); });
		add(Id::Rainbow, 7200., dayTime);
		add(Id::Ghost, 600., [this] { return ghost; }, 100.);

		// Rare: from 2.5 to 6 hours of the sky on screen, at the default rate.
		add(Id::Cow, 18000., night, 3.);
		add(Id::CatBalloon, 18000., dayTime, 3.);
		add(Id::Ship, 28800., night, 3.);
		add(Id::Legion, 28800., dayTime, 3.);
		add(Id::Dino, 43200., dayTime, 3.);
		add(Id::Hero, 43200., dayTime, 3.);
		add(Id::Flash, 43200., dayTime, 3.);
		add(Id::CatMoon, 43200., always, 1.);
		automatic.back().possible = moonVisible;
		add(Id::Lunar, 72000., always, 1.);
		automatic.back().possible = moonVisible;
		add(Id::Solar, 72000., always, 1.);
		automatic.back().possible = sunVisible;

		// These usually answer to what happens in the chat.
		add(Id::Congrats, 28800., always, 1.);
		add(Id::Banana, 43200., always, 1.);

		// Holidays: often on their date, sometimes on any other.
		holiday(Id::NewYear, 180., [this] {
			return isDate(0, 1) && minutes < 20.;
		});
		holiday(Id::Santa, 900., [this] {
			return isDate(11, 31) && isNight();
		});
		holiday(Id::Hearts, 1800., [this] { return isDate(1, 14); });
		holiday(Id::AprilFirst, 1800., [this] { return isDate(3, 1); });
		holiday(Id::AprilTwelfth, 1200., [this] { return isDate(3, 12); });
		holiday(Id::Witch, 600., [this] { return halloween() && isNight(); });
		holiday(Id::ZgBirthday, 3600., [this] { return isDate(9, 23); });
		add(Id::MyBirthday, kHolidayOtherMean, always, 1.);

		// An addition to the chances above on some dates and seasons, never
		// out of them.
		const auto only = [&](
				Id id,
				double mean,
				std::function<bool()> favorable) {
			automatic.push_back({ id, mean, 0., std::move(favorable) });
		};
		only(Id::Aurora, 21600., [this] {
			return isNight() && season() != 0;
		});
		only(Id::Ufo, 300., [this] { return isDate(3, 1); });
	}
	// How many different automatic events are on screen now. Answers to the
	// chat and helper particles are not counted.
	int busyEvents() const {
		auto ids = std::array<bool, size_t(Id::Fireworks) + 1>();
		auto result = 0;
		for (const auto &e : events) {
			switch (e.id) {
			case Id::Sent:
			case Id::Reaction:
			case Id::Pigeon:
			case Id::Deleted:
			case Id::Burst:
			case Id::Rise:
				continue;
			default:
				break;
			}
			auto &seen = ids[size_t(e.id)];
			if (!seen) {
				seen = true;
				++result;
			}
		}
		return result;
	}
	void rollAutomatic(double dt) {
		// The more is already on screen, the smaller the chance of one more.
		// Not a hard limit: three or four at once still happen, just rarely.
		static constexpr double kCrowd[] = { 1., .55, .2, .07, .02 };
		const auto busy = std::min(busyEvents(), int(std::size(kCrowd)) - 1);
		const auto rate = eventRate * kCrowd[busy];
		for (const auto &a : automatic) {
			if (a.possible && !a.possible()) {
				continue;
			}
			const auto mean = a.favorable() ? a.mean : a.otherMean;
			if (mean > 0. && F() < 1. - std::exp(-dt * rate / mean)) {
				start(a.id);
			}
		}
	}
	void checkEclipses() {
		// Dates of real eclipses, the sky shows one once on such a date.
		static const int lunar[][3] = {
			{ 2026, 7, 28 }, { 2027, 7, 17 }, { 2028, 0, 12 }, { 2028, 6, 6 },
			{ 2028, 11, 31 }, { 2029, 5, 26 }, { 2029, 11, 20 }, { 2030, 5, 15 } };
		static const int solar[][3] = {
			{ 2026, 7, 12 }, { 2027, 1, 6 }, { 2027, 7, 2 }, { 2028, 0, 26 },
			{ 2028, 6, 22 }, { 2029, 0, 14 }, { 2030, 5, 1 }, { 2030, 10, 25 } };
		const auto today = dayNumber();
		if (eclipseDay == today) {
			return;
		}
		const auto is = [&](const int (&list)[8][3]) {
			for (const auto &date : list) {
				if (date[0] == year && date[1] == month && date[2] == day) {
					return true;
				}
			}
			return false;
		};
		if (is(lunar) && isNight()) {
			eclipseDay = today;
			start(Id::Lunar);
		} else if (is(solar) && isDay()) {
			eclipseDay = today;
			start(Id::Solar);
		}
	}

	// ---------- the sky itself ----------
	void updatePalette() {
		auto p = keyPalette(phase());
		const auto dayShare = 1. - p.star;
		if (chatOpen && soft) {
			p.sky[7] = Mix(p.sky[7], p.sky[5], .55);
			p.sky[6] = Mix(p.sky[6], p.sky[5], .35);
		}
		switch (season()) {
		case 0:
			for (auto i = 0; i != 3; ++i) {
				p.hill[i] = Mix(
					p.hill[i],
					(dayShare > .5) ? C(0xDEE7F5) : C(0x6E7CBE),
					(.62 - i * .08) * std::max(.35, dayShare));
			}
			break;
		case 1: {
			const Col spring[] = { C(0x6CC46A), C(0x52AA5C), C(0x3E8C4E) };
			for (auto i = 0; i != 3; ++i) {
				p.hill[i] = Mix(p.hill[i], spring[i], .55 * dayShare);
			}
		} break;
		case 3: {
			const Col autumn[] = { C(0xD67E34), C(0xB05428), C(0x7E3E28) };
			for (auto i = 0; i != 3; ++i) {
				p.hill[i] = Mix(p.hill[i], autumn[i], .7 * dayShare);
			}
		} break;
		}
		// The ground under the hills follows their color and the season.
		p.hill[3] = Mix(p.hill[2], C(0x000000), .2);
		palette = p;
	}
	void paintMoon(const Spot &moon) {
		if (halloween()) {
			disc(C(0xF07A1E), moon.x, moon.y, 6);
			rect(0x3A1E12, moon.x - 3, moon.y - 2, 2, 2);
			rect(0x3A1E12, moon.x + 2, moon.y - 2, 2, 2);
			rect(0x3A1E12, moon.x - 3, moon.y + 2, 7, 1);
			rect(0x3A1E12, moon.x - 2, moon.y + 3, 1, 1);
			rect(0x3A1E12, moon.x + 1, moon.y + 3, 1, 1);
			rect(0x3C8F4F, moon.x, moon.y - 8, 2, 2);
			return;
		}
		const auto age = (forceFull > 0. || lunarRed > 0.) ? .5 : moonAge();
		const auto color = Mix(C(0xEDE6FF), C(0xC43A28), lunarRed);
		const auto cp = std::cos(2. * kPi * age);
		const auto r = 5;
		for (auto dy = -r; dy <= r; ++dy) {
			const auto hw = std::sqrt(double(r * r - dy * dy));
			const auto limit = int(std::floor(hw));
			for (auto dx = -limit; dx <= limit; ++dx) {
				const auto lit = (age <= .5) ? (dx >= hw * cp) : (dx <= -hw * cp);
				if (lit) {
					put(moon.x + dx, moon.y + dy, color);
				}
			}
		}
		if (age > .45 && age < .55 && lunarRed <= 0.) {
			rect(0xCFC6EE, moon.x - 2, moon.y - 2, 2, 1);
			rect(0xCFC6EE, moon.x + 1, moon.y + 1, 2, 1);
			rect(0xCFC6EE, moon.x - 1, moon.y + 2, 1, 1);
		}
	}
	void paintHill(int i, Col color) {
		const auto &list = hills[i];
		for (auto q = 0; q != int(list.size()); ++q) {
			const auto x = (q - kHillMargin) * 3 + hillOffsetX[i];
			const auto y = list[q] + hillOffsetY;
			rect(color, x, y, 3, H - y);
		}
	}
	void paintLayer(int n) {
		for (auto &e : events) {
			if (e.layer == n && e.paint) {
				e.paint(e);
			}
		}
	}
	void ensureDrops(int n) {
		while (int(drops.size()) < n) {
			drops.push_back({ F() * W, F() * H, F() * 6., 4. + F() * 4., 0 });
		}
	}
	void paintWeather(int w, double dt, double dark) {
		if (dark > 0.) {
			alpha = dark;
			rect(0x1E2440, 0, 0, W, H);
			alpha = 1.;
		}
		if (w == ZG_SKY_WEATHER_RAIN || w == ZG_SKY_WEATHER_STORM) {
			ensureDrops(120);
			const auto storm = (w == ZG_SKY_WEATHER_STORM);
			alpha = .75;
			for (auto i = 0; i != (storm ? 120 : 80); ++i) {
				auto &o = drops[i];
				o.y += dt * 75.;
				o.x -= dt * (storm ? 26. : 12.);
				if (o.y > H) {
					o.y = std::fmod(o.y, double(H));
					o.x = F() * W;
				}
				if (o.x < 0.) {
					o.x = std::fmod(o.x, double(W)) + W;
				}
				rect(0xCFE3FF, int(std::round(o.x)), int(std::round(o.y)), 1, 2);
			}
			alpha = 1.;
		}
		if (w == ZG_SKY_WEATHER_SNOW || w == ZG_SKY_WEATHER_BLIZZARD) {
			ensureDrops(220);
			const auto blizzard = (w == ZG_SKY_WEATHER_BLIZZARD);
			for (auto i = 0; i != (blizzard ? 220 : 70); ++i) {
				auto &o = drops[i];
				o.y += dt * (blizzard ? o.v * 5. : o.v);
				o.x += blizzard ? (-dt * 46.) : (std::sin(T * .8 + o.d) * dt * 2.);
				if (o.y > H) {
					o.y = std::fmod(o.y, double(H));
					o.x = F() * W;
				}
				if (o.x < 0.) {
					o.x = std::fmod(o.x, double(W)) + W;
				}
				put(int(std::round(o.x)), int(std::round(o.y)), C(0xFFFFFF));
			}
		}
		if (w == ZG_SKY_WEATHER_FOG) {
			alpha = .16;
			for (auto i = 0; i != 9; ++i) {
				const auto oy = int(std::round(H * .24)) + i * int(std::round(H * .08));
				const auto off = int(std::round(std::sin(T * .12 + i) * 18.));
				rect(0xE8E6F2, off - 20, oy, W + 40, int(std::round(H * .09)));
			}
			alpha = 1.;
		}
		const auto s = season();
		if (w == ZG_SKY_WEATHER_WIND && petals.empty() && (s == 1 || s == 3)) {
			ensureDrops(30);
			const auto color = (s == 3) ? 0xE2873AU : 0xFFC4DEU;
			for (auto i = 0; i != 24; ++i) {
				auto &o = drops[i];
				o.x -= dt * 40.;
				o.y += dt * 4. + std::sin(T * 3. + o.d) * dt * 6.;
				if (o.x < 0.) {
					o.x = std::fmod(o.x, double(W)) + W;
					o.y = F() * H;
				}
				if (o.y > H) {
					o.y = std::fmod(o.y, double(H));
				}
				rect(color, int(std::round(o.x)), int(std::round(o.y)), 2, 1);
			}
		}
		if (w == ZG_SKY_WEATHER_STORM) {
			boltTimer -= dt;
			if (boltTimer <= 0.) {
				boltTimer = 3. + F() * 7.;
				flash = .7;
				boltLeft = .28;
				bolt.clear();
				auto bx = 20 + R(W - 40);
				auto by = 0;
				while (by < H * .72) {
					const auto nx = bx + R(9) - 4;
					const auto ny = by + 3 + R(6);
					bolt.push_back({ bx, by, nx, ny });
					bx = nx;
					by = ny;
				}
			}
			if (boltLeft > 0.) {
				boltLeft -= dt;
				for (const auto &s : bolt) {
					const auto st = std::max(1, std::abs(s[3] - s[1]));
					for (auto i = 0; i <= st; ++i) {
						put(
							int(std::round(s[0] + (s[2] - s[0]) * i / double(st))),
							int(std::round(s[1] + (s[3] - s[1]) * i / double(st))),
							C(0xFFFFFF));
					}
				}
			}
		}
	}
	void paint(double dt) {
		const auto ph = phase();
		const auto w = weatherNow();
		auto p = palette;
		const auto star = std::max(p.star, solarCover);
		if (solarCover > 0.) {
			const auto dark = C(0x0A0C2C);
			for (auto &c : p.sky) {
				c = Mix(c, dark, solarCover * .75);
			}
			for (auto &c : p.hill) {
				c = Mix(c, dark, solarCover * .6);
			}
			p.cloudAlpha *= 1. - solarCover;
		}
		const auto dayShare = 1. - p.star;
		const auto dark = (w == ZG_SKY_WEATHER_RAIN || w == ZG_SKY_WEATHER_BLIZZARD)
			? .28
			: (w == ZG_SKY_WEATHER_STORM)
			? .5
			: (w == ZG_SKY_WEATHER_SNOW)
			? .08
			: 0.;
		const auto s = season();
		const auto band = std::max(1, int(std::round(12. * k)));
		for (auto i = 0; i != 8; ++i) {
			rect(p.sky[i], 0, i * band, W, (i == 7) ? H : band);
		}
		for (auto i = 1; i != 8; ++i) {
			for (auto q = 0; q < W; q += 2) {
				put(q, i * band - 1, p.sky[i]);
			}
			for (auto q = 1; q < W; q += 2) {
				put(q, i * band, p.sky[i - 1]);
			}
		}
		if (star > .02
			&& w != ZG_SKY_WEATHER_STORM
			&& w != ZG_SKY_WEATHER_BLIZZARD) {
			alpha = star;
			for (const auto &o : stars) {
				const auto q = std::fmod(T + o.phase, o.period) / o.period;
				const auto c = (q < .08)
					? C(0x6F63D8)
					: (q < .18)
					? C(0xB9A8FF)
					: C(0xF4F0FF);
				const auto x = o.x + skyOffsetX;
				put(x, o.y, c);
				if (o.big) {
					rect(c, x - 1, o.y, 3, 1);
					rect(c, x, o.y - 1, 1, 3);
				}
			}
			alpha = 1.;
		}
		const auto sun = sunSpot();
		if (sun.visible && dark <= .4) {
			alpha = .22;
			disc(Mix(C(0xFF8A3D), C(0xFFF7C2), sun.q), sun.x, sun.y, 10);
			alpha = 1.;
			disc(Mix(C(0xFF9A4D), C(0xFFF2A8), sun.q), sun.x, sun.y, 6);
		}
		const auto moon = moonSpot();
		if (moon.visible && dark <= .4) {
			paintMoon(moon);
		}
		auto cloudAlpha = p.cloudAlpha;
		auto cloudColor = p.cloud;
		if (w == ZG_SKY_WEATHER_RAIN
			|| w == ZG_SKY_WEATHER_STORM
			|| w == ZG_SKY_WEATHER_BLIZZARD) {
			cloudAlpha = std::max(cloudAlpha, .7);
			cloudColor = Mix(cloudColor, C(0x464A60), .8);
		}
		if (w == ZG_SKY_WEATHER_WIND) {
			cloudAlpha = std::max(cloudAlpha, .8);
		}
		if (cloudAlpha > .02) {
			const auto speed = (w == ZG_SKY_WEATHER_WIND)
				? 6.
				: (w == ZG_SKY_WEATHER_STORM)
				? 2.
				: .3;
			alpha = cloudAlpha;
			for (const auto &o : clouds) {
				const auto px = int(std::floor(
					std::fmod(o.x * W + T * speed, W + o.width))) - o.width + skyOffsetX;
				const auto py = int(std::round(o.y * H));
				rect(cloudColor, px, py, o.width, 2);
				rect(cloudColor, px + 3, py - 2, o.width - 9, 2);
				rect(cloudColor, px + 7, py - 3, o.width - 18, 1);
				rect(cloudColor, px + 5, py + 2, o.width - 12, 1);
			}
			alpha = 1.;
		}
		paintLayer(0);
		paintHill(0, p.hill[0]);
		if (ph > 1140. && ph < 1410. && dayShare < .95) {
			for (const auto &q : city) {
				if (ph >= q.on) {
					put(q.x + hillOffsetX[0], q.y + hillOffsetY, C(0xFFD86B));
				}
			}
		}
		paintHill(1, p.hill[1]);
		paintLayer(1);
		paintHill(2, p.hill[2]);
		rect(p.hill[3], 0, int(std::round(124. * k)) + hillOffsetY, W, H);
		if (s == 0) {
			const auto cap = Mix(C(0xFFFFFF), C(0x96A2D6), p.star);
			for (auto i = 0; i != 3; ++i) {
				const auto &list = hills[i];
				for (auto q = 0; q != int(list.size()); ++q) {
					if (i == 2 || list[q] < hills[i + 1][q] - 1) {
						rect(
							cap,
							(q - kHillMargin) * 3 + hillOffsetX[i],
							list[q] + hillOffsetY,
							3,
							1);
					}
				}
			}
			static const Pal snowman = {
				{ 'K', 0x22223A }, { 'W', 0xF7FAFF }, { 'O', 0xFF8A3D } };
			static const Pal tree = { { 'G', 0x2E7A4A }, { 'B', 0x5A3A22 } };
			const auto sx = int(std::round(W * .72));
			const auto tx = int(std::round(W * .2));
			const auto ty = ridge(2, tx + 3) - 7;
			sprite(kSnowman, sx, ridge(2, sx + 3) - 10, snowman);
			sprite(kTree, tx, ty, tree);
			if (month == 11 || month == 0) {
				const auto blink = int(T * 2.) % 2;
				const int lights[5][2] = {
					{ 3, 1 }, { 1, 3 }, { 5, 3 }, { 2, 5 }, { 4, 5 } };
				for (auto i = 0; i != 5; ++i) {
					put(
						tx + lights[i][0],
						ty + lights[i][1],
						C(((i + blink) % 2) ? 0xFFE14D : 0xFF5A7A));
				}
			}
		}
		if (s == 1 && dayShare > .4) {
			alpha = dayShare;
			for (const auto &q : flowers) {
				put(q.x, ridge(q.layer, q.x) + q.dy, C(q.color));
			}
			alpha = 1.;
		}
		for (const auto &q : windows) {
			const auto lit = (q.on < q.off)
				? (ph >= q.on && ph < q.off)
				: (ph >= q.on || ph < q.off);
			if (lit) {
				put(q.x + hillOffsetX[1], q.y + hillOffsetY, C(0xFFD86B));
			}
		}
		paintLayer(2);
		if (!petals.empty()) {
			petalsLeft -= dt;
			for (auto &o : petals) {
				o.y += dt * (petalsAreLeaves ? 9. : 6.);
				o.x += dt * (petalsAreLeaves ? -7. : 5.) + std::sin(T + o.d) * dt * 3.;
				if (o.y > H) {
					o.y = std::fmod(o.y, double(H));
					o.x = F() * W;
				}
				if (o.x < -2.) {
					o.x = std::fmod(o.x, double(W)) + W;
				}
				if (o.x > W + 2.) {
					o.x = std::fmod(o.x, double(W));
				}
				rect(
					o.color,
					int(std::round(o.x)),
					int(std::round(o.y)),
					1 + (int(T * 2. + o.d) % 2),
					1);
			}
			if (petalsLeft <= 0.) {
				petals.clear();
			}
		}
		paintWeather(w, dt, dark);
		paintLayer(3);
		if (chatOpen && dim > 0.f) {
			alpha = dim;
			rect(0x080828, 0, 0, W, H);
			alpha = 1.;
		}
		if (flash > 0.) {
			alpha = std::min(.9, flash);
			rect(0xFFFFFF, 0, 0, W, H);
			alpha = 1.;
			flash = std::max(0., flash - dt * 1.6);
		}
		paintLayer(4);
		if (T < flipUntil) {
			for (auto y = 0; y != H / 2; ++y) {
				std::swap_ranges(
					pixels.begin() + y * W,
					pixels.begin() + (y + 1) * W,
					pixels.begin() + (H - 1 - y) * W);
			}
		}
	}

	int advance(double dt, ZgSkyRect *rects, int maxRects) {
		if (W <= 0 || H <= 0) {
			return 0;
		}
		T += dt;
		forceFull = std::max(0., forceFull - dt);
		paletteAge += dt;
		if (paletteAge >= kPaletteInterval) {
			paletteAge = 0.;
			updatePalette();
		}
		const auto w = weatherNow();
		if (lastWeather == ZG_SKY_WEATHER_RAIN
			&& w == ZG_SKY_WEATHER_CLEAR
			&& isDay()
			&& eventsEnabled) {
			start(Id::Rainbow);
		}
		lastWeather = w;
		for (auto i = 0; i != 3; ++i) {
			hillOffsetX[i] = int(std::round(parallaxX * (i + 1)));
		}
		hillOffsetY = int(std::round(parallaxY));
		skyOffsetX = int(std::round(parallaxX * .5));
		if (eventsEnabled) {
			rollAutomatic(dt);
			checkEclipses();
		} else {
			events.clear();
			delayed.clear();
			petals.clear();
		}
		for (auto i = int(delayed.size()) - 1; i >= 0; --i) {
			if (delayed[i].at <= T) {
				const auto callback = std::move(delayed[i].callback);
				delayed.erase(delayed.begin() + i);
				callback();
			}
		}
		for (auto i = int(events.size()) - 1; i >= 0; --i) {
			auto &e = events[i];
			e.t += dt;
			if (!e.update(e, dt)) {
				events.erase(events.begin() + i);
			}
		}
		for (auto &callback : pendingEvents) {
			callback();
		}
		pendingEvents.clear();
		paint(dt);
		return collectChanges(rects, maxRects);
	}
	int collectChanges(ZgSkyRect *rects, int maxRects) {
		auto count = 0;
		const auto push = [&](int x, int y, int w, int h) {
			if (count < maxRects && rects) {
				rects[count] = { x, y, w, h };
			}
			++count;
		};
		if (fullRepaint || previous.size() != pixels.size()) {
			fullRepaint = false;
			previous = pixels;
			push(0, 0, W, H);
			return 1;
		}
		for (auto ty = 0; ty < H; ty += kTile) {
			const auto ty1 = std::min(ty + kTile, H);
			auto runStart = -1;
			for (auto tx = 0; tx <= W; tx += kTile) {
				auto changed = false;
				if (tx < W) {
					const auto w = std::min(kTile, W - tx);
					for (auto y = ty; y != ty1 && !changed; ++y) {
						changed = std::memcmp(
							&pixels[y * W + tx],
							&previous[y * W + tx],
							w * sizeof(uint32_t)) != 0;
					}
				}
				if (changed && runStart < 0) {
					runStart = tx;
				} else if (!changed && runStart >= 0) {
					push(runStart, ty, std::min(tx, W) - runStart, ty1 - ty);
					runStart = -1;
				}
			}
			if (runStart >= 0) {
				push(runStart, ty, W - runStart, ty1 - ty);
			}
		}
		if (count > 0) {
			previous = pixels;
		}
		return std::min(count, (maxRects > 0) ? maxRects : count);
	}
	[[nodiscard]] int nextDelay() const {
		const auto w = weatherNow();
		if (w == ZG_SKY_WEATHER_RAIN
			|| w == ZG_SKY_WEATHER_STORM
			|| w == ZG_SKY_WEATHER_SNOW
			|| w == ZG_SKY_WEATHER_BLIZZARD
			|| !petals.empty()) {
			return 66;
		}
		if (!events.empty() || flash > 0.) {
			return 33;
		}
		return eventsEnabled ? 250 : 5000;
	}
};

extern "C" {

ZgSky *zg_sky_create(void) {
	const auto sky = new ZgSky();
	sky->setupAutomatic();
	return sky;
}

void zg_sky_destroy(ZgSky *sky) {
	delete sky;
}

void zg_sky_set_size(ZgSky *sky, int cols, int rows) {
	if (sky->W == cols && sky->H == rows) {
		return;
	}
	sky->W = cols;
	sky->H = rows;
	sky->pixels.assign(size_t(std::max(cols, 0)) * size_t(std::max(rows, 0)), 0xFF000000U);
	sky->rebuild();
}

void zg_sky_set_mode(ZgSky *sky, int mode) {
	if (sky->mode != mode) {
		sky->mode = mode;
		sky->paletteAge = kPaletteInterval;
	}
}

void zg_sky_set_weather(ZgSky *sky, int weather) {
	sky->weatherSetting = weather;
}

void zg_sky_set_chat(ZgSky *sky, int chat_open, float dim, int soft) {
	if (sky->chatOpen != (chat_open != 0)
		|| sky->dim != dim
		|| sky->soft != (soft != 0)) {
		sky->chatOpen = (chat_open != 0);
		sky->dim = dim;
		sky->soft = (soft != 0);
		sky->paletteAge = kPaletteInterval;
	}
}

void zg_sky_set_events(ZgSky *sky, int enabled) {
	sky->eventsEnabled = (enabled != 0);
}

void zg_sky_set_ghost(ZgSky *sky, int enabled) {
	sky->ghost = (enabled != 0);
}

void zg_sky_set_event_rate(ZgSky *sky, float rate) {
	sky->eventRate = double(rate);
}

void zg_sky_set_parallax(ZgSky *sky, float x, float y) {
	sky->parallaxX = double(std::clamp(x, -1.f, 1.f));
	sky->parallaxY = double(std::clamp(y, -1.f, 1.f));
}

void zg_sky_set_launch_point(ZgSky *sky, float x, float y) {
	sky->launchX = double(x);
	sky->launchY = double(y);
}

void zg_sky_set_time(
		ZgSky *sky,
		int year,
		int month,
		int day,
		double minutes) {
	// After a pause (the app was hidden, the laptop slept) the sky is right at
	// once, without waiting for the next slow color update.
	if (sky->year != year
		|| sky->month != month
		|| sky->day != day
		|| std::abs(sky->minutes - minutes) >= 1.) {
		sky->paletteAge = kPaletteInterval;
	}
	sky->year = year;
	sky->month = month;
	sky->day = day;
	sky->minutes = minutes;
}

void zg_sky_fire(ZgSky *sky, int what) {
	if (!sky->eventsEnabled || sky->W <= 0) {
		return;
	}
	switch (what) {
	case ZG_SKY_FIRE_SENT: sky->start(Id::Sent); break;
	case ZG_SKY_FIRE_REACTION: sky->start(Id::Reaction); break;
	case ZG_SKY_FIRE_RECEIVED: sky->start(Id::Pigeon); break;
	case ZG_SKY_FIRE_DELETED: sky->start(Id::Deleted); break;
	case ZG_SKY_FIRE_CONGRATS: sky->start(Id::Congrats); break;
	case ZG_SKY_FIRE_VOICE: sky->start(Id::Banana); break;
	case ZG_SKY_FIRE_BIRTHDAY: sky->start(Id::MyBirthday); break;
	}
}

int zg_sky_advance(
		ZgSky *sky,
		double seconds,
		ZgSkyRect *rects,
		int max_rects) {
	return sky->advance(seconds, rects, max_rects);
}

const uint32_t *zg_sky_pixels(const ZgSky *sky) {
	return sky->pixels.data();
}

int zg_sky_next_delay_ms(const ZgSky *sky) {
	return sky->nextDelay();
}

const char *zg_sky_catch(const ZgSky *sky, int col, int row) {
	for (const auto &e : sky->events) {
		if (e.rare
			&& e.bw > 0
			&& col >= e.bx - 2
			&& col <= e.bx + e.bw + 2
			&& row >= e.by - 2
			&& row <= e.by + e.bh + 2) {
			return e.rare;
		}
	}
	return nullptr;
}

} // extern "C"
