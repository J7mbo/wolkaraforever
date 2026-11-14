#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// The response curve applied to a stick position before it reaches the game. `sensitivity`
// 1 returns the position unchanged; lower values add a little dead zone and bend the
// magnitude so small movements are gentler. Direction is kept, and a full throw stays full.
CGPoint AKTouchGamepadShapeStick(CGPoint position, CGFloat sensitivity);
// Owns only our virtual device. Physical controllers and their handlers stay
// with GameController/the guest. No game events or memory are inspected.
@interface AKTouchGamepad : NSObject
- (instancetype)initWithHostView:(UIView *)host;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, readonly) BOOL visible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, copy, nullable) void (^visibilityChanged)(BOOL visible);
- (void)refresh;
- (void)toggleSettings;
// Re-read the saved layout: the launcher and the settings panel both write it, and the
// arrangement, the zones and the elements have to be what the dictionary now says.
- (void)reloadLayout;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
