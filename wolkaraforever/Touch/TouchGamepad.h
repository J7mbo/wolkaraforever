#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// The response curve applied to a stick position before it reaches the game. `sensitivity`
// 1 returns the position unchanged; lower values add a little dead zone and bend the
// magnitude so small movements are gentler. Direction is kept, and a full throw stays full.
CGPoint AKTouchGamepadShapeStick(CGPoint position, CGFloat sensitivity);
// A tap on a floating stick that the game should have: userInfo x/y, window coordinates.
// The view the game draws in clicks there.
FOUNDATION_EXPORT NSNotificationName const AKGamepadTapThroughNotification;
// A floating stick held still, then dragged: the drag belongs to the game. userInfo phase
// (began, moved, ended) and x/y in window coordinates.
FOUNDATION_EXPORT NSNotificationName const AKGamepadDragThroughNotification;
// The ring an installed interface's spinning spell wheel takes around the bottom-right corner,
// as WolkaraRoue last saved it: @{inner, outer}, each a share of the screen height, under this
// key in the standard user defaults; absent while no such wheel is on. Floating sticks leave
// that ring to the game, and the view the game draws in turns a drag there into wheel notches.
FOUNDATION_EXPORT NSString *const AKSpellWheelDefaultsKey;
// The ring in the text of a WolkaraRoue.lua saved-variables file, or nil when it has none.
NSDictionary<NSString *, NSNumber *> *_Nullable AKSpellWheelRingFromSavedVariables(NSString *text);
// Reads the newest WolkaraRoue.lua under <documents>/World of Warcraft/<edition>/WTF/Account/
// <account>/SavedVariables and publishes its ring under AKSpellWheelDefaultsKey. It reads a
// file only when a newer one appears, and with no such file it leaves the key as it is.
void AKSpellWheelPublishFromDocuments(NSString *documents);
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
