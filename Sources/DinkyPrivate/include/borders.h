#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Border windows: plain SkyLight windows owned by dinky, one per decorated window, ordered
// directly below their target so they never cover its content. The JankyBorders approach,
// reimplemented. Every function takes the border's own window ID. Main thread only.

typedef NS_ENUM(int, DinkyBorderStyle) {
    DinkyBorderStyleRound = 0,   // follows the target's corner radius
    DinkyBorderStyleSquare = 1,  // square corners, visible behind the target's rounded ones
};

typedef struct {
    double red, green, blue, alpha;  // 0...1
} DinkyBorderColor;

// A hidden, click-through, shadowless window at `scale` (1 or 2, the target display's
// backing scale). Returns 0 on failure.
uint32_t dinky_border_create(double scale);

// Reshapes and redraws the border as a `width`-point stroke hugging `frame` (the target's
// frame in global top-left coordinates) on the outside, then moves it, copies the target's
// level and orders it directly below `target`, all in one transaction.
void dinky_border_update(uint32_t border, uint32_t target, CGRect frame, int cornerRadius,
                         DinkyBorderColor color, double width, DinkyBorderStyle style);

// Moves and re-orders without redrawing: the cheap path for drags and re-tiles that keep the size.
void dinky_border_move(uint32_t border, uint32_t target, CGRect frame, double width);

// Puts the border on the target's Space. New borders start on the current Space.
void dinky_border_move_to_space(uint32_t border, uint64_t spaceID);

void dinky_border_hide(uint32_t border);
void dinky_border_show(uint32_t border, uint32_t target);
void dinky_border_destroy(uint32_t border);

// The front app's frontmost document window on a visible Space, 0 if none.
// JankyBorders get_front_window.
uint32_t dinky_border_focused_window(void);

NS_ASSUME_NONNULL_END
