# Throwaway: diagnostic prints in the BC fallback's blit path, in the prepared tree only.
p='translation/Metal/BCTextures.m'; t=open(p).read()
def put(old,new):
    global t
    assert old in t, old[:60]; t=t.replace(old,new,1)
put('''static void commitCommandBuffer(id commandBuffer, SEL selector) {
    NSMutableArray<AKBCUpload *> *uploads = objc_getAssociatedObject(commandBuffer, &uploadsKey);''',
'''static void commitCommandBuffer(id commandBuffer, SEL selector) {
    NSMutableArray<AKBCUpload *> *uploads = objc_getAssociatedObject(commandBuffer, &uploadsKey);
    fprintf(stderr, "PROBE commit %s uploads=%lu\\n", object_getClassName(commandBuffer), (unsigned long)uploads.count);''')
put('''    id commandBuffer = ((AKBCOwner *)objc_getAssociatedObject(encoder, &ownerKey)).commandBuffer;
    if (!commandBuffer) { [upload decode]; return true; }''',
'''    id commandBuffer = ((AKBCOwner *)objc_getAssociatedObject(encoder, &ownerKey)).commandBuffer;
    fprintf(stderr, "PROBE stage encoder=%s commandBuffer=%s\\n", object_getClassName(encoder), commandBuffer ? object_getClassName(commandBuffer) : "nil");
    if (!commandBuffer) { [upload decode]; return true; }''')
put('''    uint8_t *texels = staging.contents;''','''    uint8_t *texels = staging.contents;
    fprintf(stderr, "PROBE decode %ux%ux%u first source byte %u\\n", width, height, depth, bytes[offset]);''')
put('''static id blitEncoder(id commandBuffer, SEL selector) {
    id encoder = ((id (*)(id, SEL))original(commandBuffer, selector))(commandBuffer, selector);''',
'''static id blitEncoder(id commandBuffer, SEL selector) {
    id encoder = ((id (*)(id, SEL))original(commandBuffer, selector))(commandBuffer, selector);
    fprintf(stderr, "PROBE blitEncoder on %s -> %s\\n", object_getClassName(commandBuffer), encoder ? object_getClassName(encoder) : "nil");''')
put('''            hookCommandBufferClass(object_getClass(commandBuffer));''','''            hookCommandBufferClass(object_getClass(commandBuffer));
            fprintf(stderr, "PROBE hooked command buffer class %s (commit implemented by %s)\\n", object_getClassName(commandBuffer),
                    class_getName(object_getClass(commandBuffer)));''')
open(p,'w').write(t)
p='tests/test_bc_textures.m'; t=open(p).read()
old='''static void runBlit(id<MTLCommandQueue> queue, void (^encode)(id<MTLBlitCommandEncoder>), void (^beforeCommit)(void)) {
    id<MTLCommandBuffer> command = [queue commandBuffer];'''
assert old in t
t=t.replace(old, old+'''
    fprintf(stderr, "PROBE runBlit command buffer %s\\n", object_getClassName(command));''',1)
open(p,'w').write(t)
