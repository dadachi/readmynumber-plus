#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "front_image" asset catalog image resource.
static NSString * const ACImageNameFrontImage AC_SWIFT_PRIVATE = @"front_image";

/// The "front_image_background" asset catalog image resource.
static NSString * const ACImageNameFrontImageBackground AC_SWIFT_PRIVATE = @"front_image_background";

/// The "front_image_with_background" asset catalog image resource.
static NSString * const ACImageNameFrontImageWithBackground AC_SWIFT_PRIVATE = @"front_image_with_background";

#undef AC_SWIFT_PRIVATE
