
#import "GLTFPreviewViewController.h"

#import <SceneKit/SceneKit.h>
#import <GLTFKit2/GLTFKit2.h>

@interface GLTFPreviewViewController ()
@property (nonatomic, weak) IBOutlet SCNView *sceneView;
@end

@implementation GLTFPreviewViewController

- (NSString *)nibName {
    return @"PreviewViewController";
}

- (void)loadView {
    [super loadView];
    self.sceneView.backgroundColor = [NSColor colorNamed:@"BackgroundColor"];
}

- (void)preparePreviewOfFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError * _Nullable))handler {
    [GLTFAsset loadAssetWithURL:url options:@{} handler:^(float progress, GLTFAssetStatus status,
                                                          GLTFAsset *asset, NSError *error, BOOL *stop)
    {
        handler(error);
        if (asset) {
            GLTFSCNSceneSource *source = [[GLTFSCNSceneSource alloc] initWithAsset:asset];
            self.sceneView.scene = source.defaultScene;
            NSArray<GLTFSCNAnimation *> *animations = source.animations;
            GLTFSCNAnimation *defaultAnimation = animations.firstObject;
            if (defaultAnimation) {
                [self.sceneView.scene.rootNode addAnimationPlayer:defaultAnimation.animationPlayer forKey:nil];
                [defaultAnimation.animationPlayer play];
            }
            self.sceneView.scene.lightingEnvironment.contents = @"studio-ql.hdr";
            self.sceneView.scene.lightingEnvironment.intensity = 1.5;
        }
    }];
}

@end
