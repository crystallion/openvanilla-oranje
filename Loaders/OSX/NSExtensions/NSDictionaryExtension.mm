#import "NSDictionaryExtension.h"

@implementation NSMutableDictionary (ValueForKeyDefault) 
-(id)valueForKey:(NSString*)key default:(id)obj {
    id v=[self valueForKey:key];
    if (v) return v;
    [self setValue:obj forKey:key];     // this also retains the obj
    return obj;
}
@end