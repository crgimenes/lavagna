/* The Metal side both backends share: the buffer as a texture, drawn at its
   integer scale on a CAMetalLayer. */
#ifndef LAVAGNA_METAL_H
#define LAVAGNA_METAL_H

#import <QuartzCore/QuartzCore.h>

#include "lavagna_core.h"

@interface LavRenderer : NSObject
@property(nonatomic, readonly) CAMetalLayer *layer;
- (instancetype)initWithLayer:(CAMetalLayer *)layer;
/* Uploads what lav_dirty marked and draws when something changed. */
- (void)render:(lavagna *)lv;
@end

#endif
