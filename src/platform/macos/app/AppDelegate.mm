#import "AppDelegate.h"

#include "bundle_writer.h"
#include "ffmpeg_support.h"
#include "media_input.h"
#include "pdf_writer.h"
#include "transcriber.h"
#include "video_analyzer.h"

#include <filesystem>
#include <sys/sysctl.h>
#include <string>

namespace fs = std::filesystem;

@interface AppDelegate ()

@property(retain) NSWindow *window;

@property(assign) NSTextField *inputField;
@property(assign) NSTextField *outputField;
@property(assign) NSPopUpButton *modelPopup;
@property(retain) NSMutableArray *modelPaths;
@property(assign) NSPopUpButton *languagePopup;

@property(assign) NSButton *audioOnlyCheckbox;
@property(assign) NSButton *pdfCheckbox;

@property(assign) NSButton *startButton;
@property(assign) NSButton *openOutputButton;

@property(assign) NSTextField *statusLabel;
@property(assign) NSTextField *percentLabel;
@property(assign) NSProgressIndicator *progressBar;

@property(assign) NSStackView *resultsListStack;

@end

@implementation AppDelegate

#pragma mark - Lifecycle

- (void)dealloc {
    self.window = nil;
    [super dealloc];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    return NSTerminateNow;
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
}

#pragma mark - UI helpers

- (NSTextField *)makeLabel:(NSString *)text
                     font:(NSFont *)font
                    color:(NSColor *)color {
    NSTextField *label =
        [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

    [label setStringValue:text ?: @""];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:font ?: [NSFont systemFontOfSize:13.0]];
    [label setTextColor:color ?: [NSColor labelColor]];
    [label setLineBreakMode:NSLineBreakByTruncatingTail];
    [label setWantsLayer:NO];

    return label;
}

- (NSTextField *)titleLabel:(NSString *)text {
    return [self makeLabel:text
                      font:[NSFont boldSystemFontOfSize:14.0]
                     color:[NSColor labelColor]];
}

- (NSTextField *)secondaryLabel:(NSString *)text {
    return [self makeLabel:text
                      font:[NSFont systemFontOfSize:12.0]
                     color:[NSColor secondaryLabelColor]];
}

- (NSTextField *)makePathField {
    NSTextField *field =
        [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

    [field setFont:[NSFont systemFontOfSize:13.0]];
    [field setUsesSingleLineMode:YES];
    [field setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [field setWantsLayer:NO];

    [field.widthAnchor constraintGreaterThanOrEqualToConstant:500.0].active = YES;
    [field.heightAnchor constraintEqualToConstant:28.0].active = YES;

    return field;
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action {
    NSButton *button =
        [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];

    [button setTitle:title];
    [button setBezelStyle:NSBezelStyleRounded];
    [button setTarget:self];
    [button setAction:action];
    [button setWantsLayer:NO];

    [button.widthAnchor constraintGreaterThanOrEqualToConstant:104.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:30.0].active = YES;

    return button;
}

- (NSBox *)separator {
    NSBox *box = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    [box setBoxType:NSBoxSeparator];
    [box setWantsLayer:NO];
    return box;
}

- (NSStackView *)fieldSectionWithTitle:(NSString *)title
                              subtitle:(NSString *)subtitle
                                 field:(NSTextField *)field
                                button:(NSButton *)button {

    NSStackView *head =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:title],
            [self secondaryLabel:subtitle]
        ]];

    [head setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [head setSpacing:2.0];
    [head setAlignment:NSLayoutAttributeLeading];

    NSStackView *row =
        [NSStackView stackViewWithViews:@[field, button]];

    [row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [row setSpacing:10.0];
    [row setAlignment:NSLayoutAttributeCenterY];

    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    [button setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *section =
        [NSStackView stackViewWithViews:@[head, row]];

    [section setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [section setSpacing:8.0];
    [section setAlignment:NSLayoutAttributeLeading];

    [row.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;

    return section;
}

- (NSStackView *)modelSectionWithButton:(NSButton *)button
                         deviceButton:(NSButton *)deviceButton {
    NSStackView *head =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:@"3. Модель Whisper"],
            [self secondaryLabel:@"Встроенные модели + рекомендация"]
        ]];
    [head setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [head setSpacing:2.0];
    [head setAlignment:NSLayoutAttributeLeading];

    NSStackView *buttons =
        [NSStackView stackViewWithViews:@[deviceButton, button]];
    [buttons setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [buttons setSpacing:8.0];

    NSStackView *row =
        [NSStackView stackViewWithViews:@[self.modelPopup, buttons]];
    [row setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [row setSpacing:10.0];

    NSStackView *section =
        [NSStackView stackViewWithViews:@[head, row]];
    [section setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [section setSpacing:8.0];
    [row.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    return section;
}

- (NSBox *)nativePanelWithContent:(NSView *)content {
    NSBox *box =
        [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];

    [box setBoxType:NSBoxCustom];
    [box setTitlePosition:NSNoTitle];
    [box setBorderType:NSLineBorder];
    [box setBorderWidth:1.0];
    [box setCornerRadius:8.0];
    [box setFillColor:[NSColor controlBackgroundColor]];
    [box setBorderColor:[NSColor separatorColor]];
    [box setWantsLayer:NO];

    NSView *boxContent = [box contentView];
    [content setTranslatesAutoresizingMaskIntoConstraints:NO];
    [boxContent addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:boxContent.leadingAnchor constant:16.0],
        [content.trailingAnchor constraintEqualToAnchor:boxContent.trailingAnchor constant:-16.0],
        [content.topAnchor constraintEqualToAnchor:boxContent.topAnchor constant:14.0],
        [content.bottomAnchor constraintEqualToAnchor:boxContent.bottomAnchor constant:-14.0],
    ]];

    return box;
}

- (NSTextField *)resultFileLabel:(NSString *)name {
    return [self makeLabel:name
                      font:[NSFont monospacedSystemFontOfSize:11.5
                                                       weight:NSFontWeightRegular]
                     color:[NSColor secondaryLabelColor]];
}

#pragma mark - Models

- (NSString *)friendlyModelName:(NSString *)fileName {
    NSString *name = [[fileName lastPathComponent] stringByDeletingPathExtension];
    if ([name hasPrefix:@"ggml-"]) name = [name substringFromIndex:5];

    NSDictionary *labels = @{
        @"tiny": @"tiny — самая быстрая",
        @"base": @"base — быстрая",
        @"small": @"small — баланс",
        @"medium": @"medium — качество выше",
        @"large-v3": @"max — максимум качества"
    };

    NSString *label = [labels objectForKey:name];
    return label ? label : name;
}

- (void)reloadBundledModels {
    if (!self.modelPaths) self.modelPaths = [NSMutableArray array];

    [self.modelPaths removeAllObjects];
    [self.modelPopup removeAllItems];

    NSString *dir = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"models"];

    NSArray *files = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:dir error:nil];

    files = [files sortedArrayUsingSelector:
        @selector(localizedCaseInsensitiveCompare:)];

    for (NSString *file in files) {
        if (![[[file pathExtension] lowercaseString] isEqualToString:@"bin"]) continue;
        [self.modelPaths addObject:[dir stringByAppendingPathComponent:file]];
        [self.modelPopup addItemWithTitle:[self friendlyModelName:file]];
    }

    if ([self.modelPaths count] == 0) {
        [self.modelPopup addItemWithTitle:@"Нет встроенных моделей"];
        [self.modelPopup setEnabled:NO];
        return;
    }

    NSInteger preferred = 0;
    for (NSUInteger i = 0; i < [self.modelPaths count]; ++i) {
        if ([[[self.modelPaths objectAtIndex:i] lastPathComponent]
                isEqualToString:@"ggml-small.bin"]) {
            preferred = (NSInteger)i;
            break;
        }
    }
    [self.modelPopup selectItemAtIndex:preferred];
}

- (NSString *)selectedModelPath {
    NSInteger i = [self.modelPopup indexOfSelectedItem];
    if (i < 0 || i >= (NSInteger)[self.modelPaths count]) return nil;
    return [self.modelPaths objectAtIndex:(NSUInteger)i];
}

- (double)ramGB {
    uint64_t bytes = 0;
    size_t size = sizeof(bytes);
    sysctlbyname("hw.memsize", &bytes, &size, NULL, 0);
    return (double)bytes / (1024.0 * 1024.0 * 1024.0);
}

- (int)logicalCpuCount {
    int value = 1;
    size_t size = sizeof(value);
    sysctlbyname("hw.logicalcpu", &value, &size, NULL, 0);
    return value;
}

- (BOOL)isAppleSilicon {
    int arm64 = 0;
    size_t size = sizeof(arm64);
    return sysctlbyname("hw.optional.arm64", &arm64, &size, NULL, 0) == 0 && arm64 == 1;
}

- (NSInteger)indexForModel:(NSString *)key {
    NSString *target = [NSString stringWithFormat:@"ggml-%@.bin", key];
    for (NSUInteger i = 0; i < [self.modelPaths count]; ++i) {
        if ([[[self.modelPaths objectAtIndex:i] lastPathComponent] isEqualToString:target]) {
            return (NSInteger)i;
        }
    }
    return -1;
}

- (void)checkDeviceForModel:(id)sender {
    (void)sender;

    double ram = [self ramGB];
    int cpu = [self logicalCpuCount];
    BOOL arm = [self isAppleSilicon];

    NSString *recommended = @"tiny";

    if (arm) {
        if (ram >= 32.0 && cpu >= 10) recommended = @"large-v3";
        else if (ram >= 16.0 && cpu >= 8) recommended = @"medium";
        else if (ram >= 8.0) recommended = @"small";
        else recommended = @"base";
    } else {
        if (ram >= 32.0 && cpu >= 12) recommended = @"medium";
        else if (ram >= 16.0 && cpu >= 6) recommended = @"small";
        else if (ram >= 8.0) recommended = @"base";
    }

    NSArray *order = @[@"tiny", @"base", @"small", @"medium", @"large-v3"];
    NSInteger wanted = (NSInteger)[order indexOfObject:recommended];
    NSInteger selected = -1;

    for (NSInteger i = wanted; i >= 0; --i) {
        selected = [self indexForModel:[order objectAtIndex:(NSUInteger)i]];
        if (selected >= 0) break;
    }

    if (selected >= 0) [self.modelPopup selectItemAtIndex:selected];

    NSString *name = [recommended isEqualToString:@"large-v3"]
        ? @"max (large-v3)" : recommended;

    NSString *chosen = selected >= 0
        ? [[self.modelPopup selectedItem] title]
        : @"нет подходящей встроенной модели";

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText:@"Подходящая модель Whisper"];
    [a setInformativeText:[NSString stringWithFormat:
        @"Архитектура: %@\nRAM: %.0f GB\nCPU-потоков: %d\n\nРекомендация: %@\nВыбрано: %@",
        arm ? @"Apple Silicon" : @"Intel", ram, cpu, name, chosen]];
    [a runModal];
}

#pragma mark - Dynamic results

- (void)clearResultsList {
    NSArray<NSView *> *views = [[self.resultsListStack arrangedSubviews] copy];

    for (NSView *view in views) {
        [self.resultsListStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    [views release];
}

- (void)addExpectedResult:(NSString *)name {
    [self.resultsListStack addArrangedSubview:[self resultFileLabel:name]];
}

- (void)updateExpectedResults {
    if (!self.resultsListStack) {
        return;
    }

    [self clearResultsList];

    // Транскрипция создаётся всегда.
    [self addExpectedResult:@"transcript.txt"];
    [self addExpectedResult:@"transcript.srt"];

    const BOOL audioOnly =
        [self.audioOnlyCheckbox state] == NSControlStateValueOn;

    if (audioOnly) {
        return;
    }

    // Если уже выбран именно аудиофайл — кадровых результатов не будет.
    const std::string input =
        [[self.inputField stringValue] UTF8String];

    if (!input.empty()) {
        const MediaKind kind = detect_media_kind(input);

        if (kind == MediaKind::Audio) {
            return;
        }
    }

    [self addExpectedResult:@"frames/"];
    [self addExpectedResult:@"lecture_context.md"];

    const BOOL createPdf =
        [self.pdfCheckbox state] == NSControlStateValueOn;

    if (createPdf) {
        [self addExpectedResult:@"frames.pdf"];
    }
}

#pragma mark - Build UI

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    self.window =
        [[[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1120, 690)
                     styleMask:(NSWindowStyleMaskTitled |
                                NSWindowStyleMaskClosable |
                                NSWindowStyleMaskMiniaturizable |
                                NSWindowStyleMaskResizable)
                       backing:NSBackingStoreBuffered
                         defer:NO] autorelease];

    [self.window setTitle:@"LectureWhisper"];
    [self.window setDelegate:self];
    [self.window setMinSize:NSMakeSize(1000, 620)];
    [self.window center];

    NSView *root = [self.window contentView];
    [root setWantsLayer:NO];

    NSTextField *appTitle =
        [self makeLabel:@"LectureWhisper"
                   font:[NSFont boldSystemFontOfSize:28.0]
                  color:[NSColor labelColor]];

    NSTextField *appSubtitle =
        [self secondaryLabel:
            @"Локальная обработка лекций: транскрипция, кадры, PDF и контекст"];

    NSStackView *headerText =
        [NSStackView stackViewWithViews:@[appTitle, appSubtitle]];
    [headerText setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [headerText setSpacing:3.0];
    [headerText setAlignment:NSLayoutAttributeLeading];

    NSTextField *localBadge =
        [self secondaryLabel:@"●  Всё обрабатывается локально на Mac"];
    [localBadge setAlignment:NSTextAlignmentRight];

    NSStackView *header =
        [NSStackView stackViewWithViews:@[headerText, localBadge]];
    [header setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [header setAlignment:NSLayoutAttributeCenterY];

    [headerText setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [localBadge setContentHuggingPriority:NSLayoutPriorityRequired
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.inputField = [self makePathField];
    [self.inputField setDelegate:self];

    self.outputField = [self makePathField];
    self.modelPopup =
        [[[NSPopUpButton alloc] initWithFrame:NSZeroRect] autorelease];
    [self.modelPopup setWantsLayer:NO];
    [self.modelPopup.widthAnchor constraintGreaterThanOrEqualToConstant:420.0].active = YES;
    [self.modelPopup.heightAnchor constraintEqualToConstant:28.0].active = YES;
    self.modelPaths = [NSMutableArray array];


    NSButton *inputButton =
        [self makeButton:@"Выбрать…" action:@selector(chooseInput:)];

    NSButton *outputButton =
        [self makeButton:@"Выбрать…" action:@selector(chooseOutput:)];

    NSButton *modelButton =
        [self makeButton:@"Обновить" action:@selector(refreshModels:)];

    NSButton *deviceModelButton =
        [self makeButton:@"Проверить устройство"
                  action:@selector(checkDeviceForModel:)];

    self.languagePopup =
        [[[NSPopUpButton alloc] initWithFrame:NSZeroRect] autorelease];
    [self.languagePopup addItemsWithTitles:@[
        @"auto — определить автоматически",
        @"ru — русский",
        @"en — английский"
    ]];
    [self.languagePopup setWantsLayer:NO];
    [self.languagePopup.widthAnchor constraintGreaterThanOrEqualToConstant:610.0].active = YES;
    [self.languagePopup.heightAnchor constraintEqualToConstant:28.0].active = YES;

    NSStackView *languageHead =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:@"4. Язык распознавания"],
            [self secondaryLabel:@"Оставьте auto, если язык заранее неизвестен"]
        ]];
    [languageHead setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [languageHead setSpacing:2.0];
    [languageHead setAlignment:NSLayoutAttributeLeading];

    NSStackView *languageSection =
        [NSStackView stackViewWithViews:@[
            languageHead,
            self.languagePopup
        ]];
    [languageSection setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [languageSection setSpacing:8.0];
    [languageSection setAlignment:NSLayoutAttributeLeading];

    NSStackView *leftContent =
        [NSStackView stackViewWithViews:@[
            [self fieldSectionWithTitle:@"1. Входной файл"
                               subtitle:@"Аудио или видео лекции"
                                  field:self.inputField
                                 button:inputButton],
            [self separator],
            [self fieldSectionWithTitle:@"2. Папка результата"
                               subtitle:@"Куда сохранить результат обработки"
                                  field:self.outputField
                                 button:outputButton],
            [self separator],
            [self modelSectionWithButton:modelButton
                          deviceButton:deviceModelButton],
            [self separator],
            languageSection
        ]];

    [leftContent setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [leftContent setSpacing:14.0];
    [leftContent setAlignment:NSLayoutAttributeLeading];

    NSBox *leftPanel = [self nativePanelWithContent:leftContent];

    self.audioOnlyCheckbox =
        [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [self.audioOnlyCheckbox setButtonType:NSButtonTypeSwitch];
    [self.audioOnlyCheckbox setTitle:@"Только аудио"];
    [self.audioOnlyCheckbox setTarget:self];
    [self.audioOnlyCheckbox setAction:@selector(audioOnlyChanged:)];
    [self.audioOnlyCheckbox setWantsLayer:NO];

    self.pdfCheckbox =
        [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    [self.pdfCheckbox setButtonType:NSButtonTypeSwitch];
    [self.pdfCheckbox setTitle:@"Создать PDF из кадров"];
    [self.pdfCheckbox setState:NSControlStateValueOn];
    [self.pdfCheckbox setTarget:self];
    [self.pdfCheckbox setAction:@selector(pdfChanged:)];
    [self.pdfCheckbox setWantsLayer:NO];

    NSStackView *audioBlock =
        [NSStackView stackViewWithViews:@[
            self.audioOnlyCheckbox,
            [self secondaryLabel:@"Не анализировать видеоряд и кадры"]
        ]];
    [audioBlock setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [audioBlock setSpacing:2.0];
    [audioBlock setAlignment:NSLayoutAttributeLeading];

    NSStackView *pdfBlock =
        [NSStackView stackViewWithViews:@[
            self.pdfCheckbox,
            [self secondaryLabel:@"Один извлечённый кадр = одна страница PDF"]
        ]];
    [pdfBlock setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [pdfBlock setSpacing:2.0];
    [pdfBlock setAlignment:NSLayoutAttributeLeading];

    NSStackView *optionsContent =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:@"Параметры обработки"],
            audioBlock,
            pdfBlock
        ]];
    [optionsContent setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [optionsContent setSpacing:14.0];
    [optionsContent setAlignment:NSLayoutAttributeLeading];

    NSBox *optionsPanel = [self nativePanelWithContent:optionsContent];
    [optionsPanel.heightAnchor constraintEqualToConstant:175.0].active = YES;

    NSStackView *formatsContent =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:@"Поддерживаемые форматы"],
            [self secondaryLabel:@"Аудио: WAV, M4A, MP3, AAC, AIFF, CAF"],
            [self secondaryLabel:@"Видео: MP4, MOV, M4V, WebM, MKV"]
        ]];
    [formatsContent setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [formatsContent setSpacing:7.0];
    [formatsContent setAlignment:NSLayoutAttributeLeading];

    NSBox *formatsPanel = [self nativePanelWithContent:formatsContent];
    [formatsPanel.heightAnchor constraintEqualToConstant:115.0].active = YES;

    self.resultsListStack =
        [NSStackView stackViewWithViews:@[]];
    [self.resultsListStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [self.resultsListStack setSpacing:7.0];
    [self.resultsListStack setAlignment:NSLayoutAttributeLeading];

    NSStackView *resultsContent =
        [NSStackView stackViewWithViews:@[
            [self titleLabel:@"Будет создано"],
            self.resultsListStack
        ]];
    [resultsContent setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [resultsContent setSpacing:9.0];
    [resultsContent setAlignment:NSLayoutAttributeLeading];

    NSBox *resultsPanel = [self nativePanelWithContent:resultsContent];
    [resultsPanel.heightAnchor constraintEqualToConstant:200.0].active = YES;

    NSStackView *rightColumn =
        [NSStackView stackViewWithViews:@[
            optionsPanel,
            formatsPanel,
            resultsPanel
        ]];

    [rightColumn setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [rightColumn setSpacing:14.0];
    [rightColumn setAlignment:NSLayoutAttributeLeading];

    [optionsPanel.widthAnchor constraintEqualToAnchor:rightColumn.widthAnchor].active = YES;
    [formatsPanel.widthAnchor constraintEqualToAnchor:rightColumn.widthAnchor].active = YES;
    [resultsPanel.widthAnchor constraintEqualToAnchor:rightColumn.widthAnchor].active = YES;

    NSStackView *columns =
        [NSStackView stackViewWithViews:@[
            leftPanel,
            rightColumn
        ]];

    [columns setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [columns setSpacing:18.0];
    [columns setAlignment:NSLayoutAttributeTop];

    [leftPanel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [leftPanel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];

    [rightColumn.widthAnchor constraintEqualToConstant:300.0].active = YES;

    self.statusLabel = [self secondaryLabel:@"Готово к запуску"];

    self.progressBar =
        [[[NSProgressIndicator alloc] initWithFrame:NSZeroRect] autorelease];
    [self.progressBar setIndeterminate:NO];
    [self.progressBar setMinValue:0];
    [self.progressBar setMaxValue:100];
    [self.progressBar setDoubleValue:0];
    [self.progressBar setWantsLayer:NO];

    self.percentLabel = [self secondaryLabel:@"0%"];
    [self.percentLabel setAlignment:NSTextAlignmentRight];
    [self.percentLabel.widthAnchor constraintEqualToConstant:42.0].active = YES;

    NSStackView *progressValue =
        [NSStackView stackViewWithViews:@[
            self.progressBar,
            self.percentLabel
        ]];

    [progressValue setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [progressValue setSpacing:10.0];
    [progressValue setAlignment:NSLayoutAttributeCenterY];

    self.startButton =
        [self makeButton:@"Начать обработку"
                  action:@selector(startProcessing:)];
    [self.startButton setKeyEquivalent:@"\r"];
    [self.startButton.widthAnchor constraintEqualToConstant:190.0].active = YES;

    self.openOutputButton =
        [self makeButton:@"Открыть результат"
                  action:@selector(openOutput:)];
    [self.openOutputButton setHidden:YES];
    [self.openOutputButton.widthAnchor constraintEqualToConstant:190.0].active = YES;

    NSStackView *progressRow =
        [NSStackView stackViewWithViews:@[
            progressValue,
            self.startButton,
            self.openOutputButton
        ]];

    [progressRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [progressRow setSpacing:12.0];
    [progressRow setAlignment:NSLayoutAttributeCenterY];

    [progressValue setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *progressContent =
        [NSStackView stackViewWithViews:@[
            self.statusLabel,
            progressRow
        ]];

    [progressContent setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [progressContent setSpacing:8.0];
    [progressContent setAlignment:NSLayoutAttributeLeading];

    [progressRow.widthAnchor constraintEqualToAnchor:progressContent.widthAnchor].active = YES;

    NSBox *progressPanel = [self nativePanelWithContent:progressContent];

    NSStackView *rootStack =
        [NSStackView stackViewWithViews:@[
            header,
            columns,
            progressPanel
        ]];

    [rootStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [rootStack setSpacing:18.0];
    [rootStack setAlignment:NSLayoutAttributeLeading];
    [rootStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [rootStack setWantsLayer:NO];

    [root addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:26.0],
        [rootStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-26.0],
        [rootStack.topAnchor constraintEqualToAnchor:root.topAnchor constant:24.0],
        [rootStack.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-22.0],

        [header.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [columns.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],
        [progressPanel.widthAnchor constraintEqualToAnchor:rootStack.widthAnchor],

        [leftPanel.widthAnchor constraintGreaterThanOrEqualToConstant:720.0],
        [columns.heightAnchor constraintGreaterThanOrEqualToConstant:455.0]
    ]];

    [self updateExpectedResults];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Dynamic actions

- (void)audioOnlyChanged:(id)sender {
    (void)sender;

    const BOOL audioOnly =
        [self.audioOnlyCheckbox state] == NSControlStateValueOn;

    [self.pdfCheckbox setEnabled:!audioOnly];

    if (audioOnly) {
        [self.pdfCheckbox setState:NSControlStateValueOff];
    }

    [self updateExpectedResults];
}

- (void)pdfChanged:(id)sender {
    (void)sender;
    [self updateExpectedResults];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if ([notification object] == self.inputField) {
        [self updateExpectedResults];
    }
}

#pragma mark - File pickers

- (void)chooseInput:(id)sender {
    (void)sender;

    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];

    [panel setAllowedFileTypes:@[
        @"wav", @"m4a", @"mp3", @"aac", @"aif", @"aiff", @"caf",
        @"mp4", @"mov", @"m4v", @"webm", @"mkv"
    ]];

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSString *path = [[[panel URLs] firstObject] path];
    [self.inputField setStringValue:path];

    if ([[self.outputField stringValue] length] == 0) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        NSString *stem =
            [[path lastPathComponent] stringByDeletingPathExtension];

        [self.outputField
            setStringValue:
                [dir stringByAppendingPathComponent:
                    [stem stringByAppendingString:@"_result"]]];
    }

    [self updateExpectedResults];
}

- (void)chooseOutput:(id)sender {
    (void)sender;

    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:YES];

    if ([panel runModal] == NSModalResponseOK) {
        [self.outputField
            setStringValue:[[[panel URLs] firstObject] path]];
    }
}

- (void)refreshModels:(id)sender {
    (void)sender;
    [self reloadBundledModels];
}

- (void)openOutput:(id)sender {
    (void)sender;

    NSString *path = [self.outputField stringValue];

    if ([path length] == 0) {
        return;
    }

    [[NSWorkspace sharedWorkspace] openFile:path];
}

#pragma mark - Processing state

- (void)setProcessingUIEnabled:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.inputField setEnabled:enabled];
        [self.outputField setEnabled:enabled];
        [self.modelPopup setEnabled:enabled && [self.modelPaths count] > 0];
        [self.languagePopup setEnabled:enabled];
        [self.audioOnlyCheckbox setEnabled:enabled];

        if (enabled) {
            const BOOL audioOnly =
                [self.audioOnlyCheckbox state] == NSControlStateValueOn;
            [self.pdfCheckbox setEnabled:!audioOnly];
        } else {
            [self.pdfCheckbox setEnabled:NO];
        }
    });
}

- (void)setProgress:(int)value status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        const int clamped = MAX(0, MIN(100, value));

        [self.progressBar setDoubleValue:clamped];
        [self.percentLabel
            setStringValue:[NSString stringWithFormat:@"%d%%", clamped]];

        if (status) {
            [self.statusLabel setStringValue:status];
        }
    });
}

- (void)showError:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setProcessingUIEnabled:YES];

        [self.startButton setHidden:NO];
        [self.openOutputButton setHidden:YES];
        [self.startButton setEnabled:YES];

        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Ошибка"];
        [alert setInformativeText:message ?: @"Неизвестная ошибка."];
        [alert runModal];
    });
}

- (NSString *)selectedLanguageCode {
    switch ([self.languagePopup indexOfSelectedItem]) {
        case 1: return @"ru";
        case 2: return @"en";
        default: return @"auto";
    }
}

#pragma mark - Processing

- (void)startProcessing:(id)sender {
    (void)sender;

    const std::string input =
        [[self.inputField stringValue] UTF8String];

    const std::string output =
        [[self.outputField stringValue] UTF8String];

    NSString *selectedModel = [self selectedModelPath];
    const std::string model =
        selectedModel ? [selectedModel UTF8String] : "";

    const std::string language =
        [[self selectedLanguageCode] UTF8String];

    const bool audioOnly =
        [self.audioOnlyCheckbox state] == NSControlStateValueOn;

    const bool createPdf =
        [self.pdfCheckbox state] == NSControlStateValueOn;

    if (input.empty() || output.empty() || model.empty()) {
        [self showError:
            @"Выбери входной файл, папку результата и модель Whisper."];
        return;
    }

    [self setProcessingUIEnabled:NO];
    [self.startButton setEnabled:NO];
    [self.startButton setHidden:NO];
    [self.openOutputButton setHidden:YES];

    [self setProgress:0 status:@"Подготовка…"];

    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            @autoreleasepool {
                std::error_code ec;
                fs::create_directories(output, ec);

                if (ec) {
                    [self showError:@"Не удалось создать папку результата."];
                    return;
                }

                const MediaKind kind = detect_media_kind(input);

                if (kind == MediaKind::Unknown) {
                    [self showError:@"Этот формат пока не поддерживается."];
                    return;
                }

                std::string audioPath;
                std::string temporaryAudio;
                std::string mediaError;

                [self setProgress:
                    2
                    status:(kind == MediaKind::Video
                        ? @"Извлечение аудио из видео…"
                        : @"Подготовка аудио…")];

                if (!prepare_audio_source(
                        input,
                        kind,
                        audioPath,
                        temporaryAudio,
                        mediaError)) {

                    NSString *msg =
                        [NSString stringWithUTF8String:mediaError.c_str()];

                    [self showError:msg];
                    return;
                }

                VideoAnalysisResult videoResult;
                const bool analyzeFrames =
                    kind == MediaKind::Video && !audioOnly;

                if (analyzeFrames) {
                    const fs::path framesDir =
                        fs::path(output) / "frames";

                    [self setProgress:5 status:@"Поиск ключевых кадров…"];

                    if (!analyze_video(
                            input,
                            framesDir.string(),
                            videoResult,
                            3.0,
                            12.0)) {

                        std::string ffmpegVideoError;

                        [self setProgress:
                            7
                            status:@"Пробую анализ видео через ffmpeg…"];

                        if (!analyze_video_with_ffmpeg(
                                input,
                                framesDir.string(),
                                videoResult,
                                3.0,
                                12.0,
                                ffmpegVideoError)) {

                            remove_temporary_file(temporaryAudio);

                            NSString *msg =
                                [NSString stringWithUTF8String:
                                    ffmpegVideoError.c_str()];

                            [self showError:
                                ([msg length]
                                    ? msg
                                    : @"Не удалось проанализировать видеоряд.")];

                            return;
                        }
                    }
                }

                TranscriptionResult transcript;

                const bool ok =
                    transcribe_audio_file(
                        audioPath,
                        model,
                        language,
                        6,
                        transcript,
                        [self, analyzeFrames](
                            int p,
                            const std::string &
                        ) {
                            const int mapped =
                                analyzeFrames
                                    ? 35 + static_cast<int>(p * 0.60)
                                    : p;

                            NSString *status =
                                [NSString stringWithFormat:
                                    @"Распознавание речи: %d%%",
                                    p];

                            [self setProgress:mapped status:status];
                        }
                    );

                remove_temporary_file(temporaryAudio);

                if (!ok) {
                    [self showError:
                        @"Ошибка Whisper при распознавании аудио."];
                    return;
                }

                const fs::path outDir(output);

                [self setProgress:94 status:@"Сохранение транскрипции…"];

                write_transcript_txt(
                    (outDir / "transcript.txt").string(),
                    transcript
                );

                write_transcript_srt(
                    (outDir / "transcript.srt").string(),
                    transcript
                );

                if (analyzeFrames) {
                    [self setProgress:
                        96
                        status:@"Создание контекста лекции…"];

                    write_video_context_markdown(
                        (outDir / "lecture_context.md").string(),
                        transcript,
                        videoResult
                    );

                    if (createPdf) {
                        [self setProgress:
                            98
                            status:@"Создание PDF из кадров…"];

                        std::string pdfError;

                        if (!create_frames_pdf(
                                (outDir / "frames").string(),
                                (outDir / "frames.pdf").string(),
                                pdfError)) {

                            NSString *msg =
                                [NSString stringWithUTF8String:
                                    pdfError.c_str()];

                            [self showError:
                                ([msg length]
                                    ? msg
                                    : @"Не удалось создать PDF из кадров.")];

                            return;
                        }
                    }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setProcessingUIEnabled:YES];
                    [self setProgress:100 status:@"Готово"];

                    [self.startButton setHidden:YES];
                    [self.startButton setEnabled:YES];
                    [self.openOutputButton setHidden:NO];

                    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                    [alert setMessageText:@"Обработка завершена"];
                    [alert setInformativeText:
                        @"Все файлы сохранены в папку результата."];
                    [alert addButtonWithTitle:@"Открыть папку"];
                    [alert addButtonWithTitle:@"Закрыть"];

                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        [self openOutput:nil];
                    }
                });
            }
        }
    );
}

@end
