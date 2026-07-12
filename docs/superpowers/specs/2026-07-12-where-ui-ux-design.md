# Where UI/UX 设计规格（Task 12）

## 设计目标

Where 应像一本被认真使用的家庭物品索引：温暖、安静、可信，而不是照片管理器或仓库后台。照片负责回答“在哪里”，物品剪影负责回答“长什么样”，文字只帮助确认和行动。界面优先使用原生 SwiftUI 导航、搜索、表单和 iOS 26 Liquid Glass；品牌色用于定位点、选中态和关键动作，不给每个容器都加玻璃或卡片。

本规格是现有已批准产品设计的视觉与交互细化，不改变数据模型或 MVP 范围。

## 设计令牌

### 色彩

所有颜色使用 Asset Catalog 的 light/dark variants，不在页面内散落 RGB 值。

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `WhereCanvas` | `#F7F1E7` | `#171A17` | 照片之外的温暖底色、空状态背景 |
| `WhereSurface` | `#FFF9EF` | `#222620` | 普通内容表面、剪影回退卡片 |
| `WhereInk` | `#173F35` | `#E8F0E9` | 主文字、图标、轮廓 |
| `WhereSecondaryInk` | `#657067` | `#AAB4AB` | 次要文字 |
| `WhereOrange` | `#E89A4A` | `#E6A35F` | 暖色品牌、空图占位 |
| `WherePin` | `#D95C4A` | `#F07462` | 定位点、选中状态、关键强调 |
| `WherePaper` | `#F2DDB8` | `#C9AB7A` | 剪影卡片背面 |
| `WhereDanger` | system red | system red | 仅删除与错误 |

关键原则：正文以系统 `primary/secondary` 为首选，品牌 token 用于需要建立识别的部位。定位点使用 `WherePin`，不能依赖全局 accent tint 偶然着色。

### 字体

- 全部使用 San Francisco 和语义字体，支持 Dynamic Type。
- 页面标题：系统 `.largeTitle` / NavigationStack 默认标题。
- 场景名称、选中物品名：`.headline`；关键位置说明可用 `.subheadline.weight(.medium)`。
- 正文与输入：`.body`；辅助信息：`.subheadline`；标签：`.caption.weight(.medium)`。
- 剪影背面正文仍由现有 Core Text 动态指标驱动，不使用固定字号；日期最多一行并使用 `.caption2` 对应指标。
- 不对中文名称使用大写、字距拉伸或超细字重。

### 间距与形状

- 基础间距单位 4 pt；页面边距 16，紧密间距 8，常规 12，区块间距 20/24。
- 可点击区域最小 44×44 pt。
- 图片/主卡片圆角 20；小表面 14；标签使用 capsule。
- 场景网格横向 gutter 12，页面边距 16；两列卡片在常见 iPhone 宽度保持至少 160 pt。
- 阴影只用于抬起的照片卡片：黑色 8% / blur 16 / y 6；Dark Mode 降到 0–4%。不要给列表行、标签和玻璃底栏重复加阴影。

## Liquid Glass 使用边界

- 保留系统 TabView 与 `tabViewBottomAccessory` 生成的玻璃底栏；独立加号使用 `.buttonStyle(.glassProminent)`，这是品牌关键动作。
- 加号与两个 Tab 在系统底栏中保持空间分组：左侧“场景 / 所有物品”，右侧独立加号。inline placement 只显示 `plus` 图标，expanded placement 显示“添加场景”。
- 加载/保存 HUD 可使用一个非交互 `.glassEffect(.regular, in: .rect(cornerRadius: 16))`，包含进度和明确动词。
- 多个自定义玻璃元素同时出现时才放进 `GlassEffectContainer`；普通照片卡、表单 section、标签、剪影卡背面不用玻璃。
- 只有可点击玻璃使用 `.interactive()`；装饰/进度 HUD 不使用 interactive。
- App 最低 iOS 26，无需维护旧系统视觉 fallback，但组件仍应避免把 Glass 当作内容层背景。

## App Shell

- 各 Tab 保持独立 NavigationStack 和滚动位置。
- 当前 `RootTabView` 的结构正确；Task 12 只需要品牌 tint 和 Items 实页接入，不要自绘底栏。
- 加号始终表示“新建场景并记录物品”，无长按菜单，避免和“在已有场景中添加物品”混淆。已有场景加物品留在场景详情的菜单内。
- 加号标签应在 accessibility 中始终为“添加场景”，expanded 视觉文案也保持一致。

## 场景 Tab

### 场景网格

- 页面使用原生大标题“场景”。网格从标题下方 8 pt 开始。
- 场景卡片是“照片 + 卡片外文字”，不要再套一层有边框的容器：照片比例建议 4:3，高度随宽度变化，不固定 130 pt；图片填充裁切。
- 照片左下角可覆盖一枚小型暖白 material capsule，显示“6 件物品”；卡片下方只保留场景名。这样在浏览时先识别空间，再读名称。
- 缺图时使用 `WhereOrange` 12% 的温暖占位，图标用 `photo.badge.exclamationmark`，并保留场景名与数量。
- 长按删除可保留；应另有明确 contextMenu label。删除确认明确“场景及 6 件物品”。

### 场景详情

- 照片是主体，黑色只出现在照片 aspect-fit 的 letterbox 区域，不应成为整页品牌背景。
- 默认不选定位点；点击定位点后：点从 20 增到 28、3 pt 浅色描边、轻微 scale spring，并出现贴近定位点的名称标签。再次点击其他点直接切换。
- 名称标签改为内容自适应高度，不固定 58 pt；最多两行，超大字体时允许三行或将标签放到照片下方的选中物品信息条。
- 照片下方提供选中物品信息条：名称、位置说明，以及“编辑”按钮。这比只在照片上悬浮标签更适合 VoiceOver 与 Dynamic Type。
- 顶部 `ellipsis` 菜单保留编辑、添加物品、删除。Task 12 必须移除“即将推出”占位并只展示真正可用动作；否则隐藏尚未实现的项。

## 所有物品 Tab

这是一个单页选择界面，不推送独立详情。

### 页面层级

1. 大标题“所有物品”。
2. 顶部位置照片区域，横向边距 16，圆角 20，建议 16:10；未选择时高度可收窄到 148 pt，显示“选择一个物品查看它的位置”。
3. 选择后，照片只高亮目标物品；照片下方紧贴名称和位置说明。切换选中项使用 180–240 ms crossfade，不用大幅位移动画。
4. 若有物品外观图，在位置照片和搜索之间显示居中的剪影卡片，最大高 220–260 pt；没有外观图时不保留空白卡片区域。
5. `.searchable(text:, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索名称、别名或标签")`。
6. 物品列表。

### 物品行

- 高度不锁死，最小 68 pt。左侧 48×48 的主体缩略图；没有照片用暖橙底 `shippingbox`。
- 中间为名称和最多两枚标签；标签超出显示“+N”，避免横向挤压名称。
- 右侧用 `location.fill` 或 checkmark 表达当前选中，不使用 navigation chevron，因为点击不会进入下一页。
- 选中行增加淡 `WherePin` 背景、左侧 3 pt 指示条或 checkmark；不可仅改变文字颜色。
- 搜索空白展示全部，未自动选择。查询无结果时文案为“没有找到‘{query}’”，并建议尝试别名或标签。

### 顶部位置照片

- ScenePhotoView 在 Items 页传入唯一 selected ID；其它 pin 以 30–40% opacity 或不展示，目标 pin 保持完整红色、白描边和名称。
- 场景照片缺失时显示“照片不可用”，但仍显示场景名、位置说明和外观卡。
- 图片具备组合 accessibility label：“{物品名} 位于 {场景名}。{位置说明}”。定位点本身保持可聚焦。

## 添加 / 拍摄流程

### 步骤一：场景照片与名称

- 首次进入即弹来源选择可保留；取消来源后页面仍应清楚显示大尺寸照片选择区。
- 选择区 4:3，使用相机图标、标题“添加场景照片”、辅助文案“拍照或从相册选择”。有图后覆盖一个右下角 glass 小按钮“更换”。
- 名称使用有明确 label 的输入区，不只依赖 placeholder；例子“玄关”作为 footer/hint。
- 底部主按钮“下一步：标记物品”，宽度填满，紧靠安全区上方。键盘出现时可见且不遮挡输入。

### 步骤二：多定位点编辑

- 照片占尽可能多空间；底部 instruction/status bar 显示“轻点照片添加物品”与“已标记 N 件”。
- 新增点：在点击处先出现一个短促 pin drop 动画并立即打开 Item Sheet；取消 Sheet 时点消失。
- 现有点：点击编辑、拖动移动、长按删除。拖动开始用 selection haptic，越过照片边界时保持最后合法位置，不突然跳转。
- 选中点除尺寸和描边外，在照片下方显示名称；未选点仍可见但降低视觉权重。
- “完成”是底部 prominent action；0 件物品时仍可保存场景，但需确认“还没有标记物品，仍要完成吗？”，或若产品决定不允许空场景则直接禁用并解释。实现时必须选定一种；推荐允许空场景以支持先拍后整理。

### 物品 Sheet

- 使用 `.large` 为默认 detent；medium 容易让键盘与照片区争夺空间。允许下拉到 medium 仅在没有键盘时。
- 按顺序分组：名称（必填）→ 位置说明 → 标签 → 别名 → 备忘 → 物品照片。最常用字段优先。
- 标签与别名最终应显示为 token/chip 编辑器；若 MVP 暂用逗号文本，label 必须写清“用逗号分隔”，保存时视觉反馈已去重。
- 物品照片选择区优先展示透明 cutout，背景使用棋盘格不合适；使用 `WhereCanvas` 让透明边界自然可见。
- 保存时按钮变为 `ProgressView + “保存中”`，禁用重复操作但不清空表单。

### 主体选择

- 将当前英文界面全部本地化为中文。
- 图像占主空间；底部说明“轻点要保留的物品”。候选按钮使用“主体 1 / 2”，选中候选同时显示 checkmark、描边和 accessibility selected trait。
- 底部两个动作层级：次要“使用原图”，主要“确认主体”。分析失败时“使用原图”成为唯一主要动作。

## 剪影翻转卡

- 正面不加矩形卡底，透明主体悬浮在 `WhereCanvas` 上；限制在 220–260 pt 高度并保留 16 pt breathing room。
- 正面底部可显示一枚轻量胶囊“轻点查看备忘”，首次选中时出现，随后淡出；VoiceOver 仍使用完整 hint。
- 背面使用 `WherePaper` 填充现有 alpha 安全轮廓，文字使用深墨绿而非纯黑。不要给轮廓外再套圆角矩形，除非布局算法触发 fallback。
- 卡片点击翻转使用 420–460 ms spring、轻 impact；Reduce Motion 下 crossfade 180 ms 且不旋转。
- 背面溢出按钮统一中文“查看完整备忘”；空间不足时显示“详情”。记录时间统一中文本地化“记录于 …”。
- 完整备忘 Sheet 是查看/编辑的唯一矩形界面；字数只在编辑状态显示，文案中文化。

## 状态设计

### 空状态

- 无场景：“还没有场景 / 添加一张家里的照片，开始记录物品位置”，下方可提供与右下角加号相同的主按钮作为显式入口。
- 无物品：“还没有物品 / 在场景照片上添加定位点后，它们会出现在这里”。
- Items 有列表但未选中：顶部保持引导，不自动选择。
- 搜索无结果：保留搜索框和清除能力，不显示全局添加主按钮以免误导。

### 加载

- 首次数据库加载短于 300 ms 不闪 skeleton；超过 300 ms 显示 2–4 个稳定占位块或居中进度。
- 图片单独加载时保留卡片尺寸，使用暖底占位，避免网格跳动。
- 保存、分割处理用带动词的阻塞 HUD；加载列表不阻塞 Tab 切换。

### 错误

- 页面加载错误使用 ContentUnavailableView + prominent“重试”。
- 可恢复的图片/清理错误使用 inline banner，不占用 toolbar 作为唯一入口。
- 表单校验贴近相关字段，并在提交时把焦点移到第一个错误；不要只在表单底部显示红字。
- 删除与权限沿用系统 alert/confirmation dialog；destructive 颜色只用于真正破坏性动作。

## 动效与触觉

- 选择物品/定位点：`.snappy(duration: 0.22)` 或等价系统 spring；selection haptic。
- 新增 pin：从 0.78 scale + 0 opacity 到 1；light impact。
- 保存完成：success haptic，并切回 Scenes；不加庆祝动画。
- 删除确认后：warning haptic；列表删除用系统过渡。
- 翻卡：medium impact 在越过 90° 时触发；Reduce Motion 改为 crossfade。
- Respect Reduce Motion、Reduce Transparency 和 Differentiate Without Color。Reduce Transparency 时 glass HUD 应提供不透明 `WhereSurface` fallback。

## 无障碍与 Dynamic Type

- 交互点/按钮最小 44×44；定位点视觉尺寸可以 20–30，但命中框为 44。
- 场景卡合并读作“玄关，6 件物品，按钮”。上下文删除提供 custom action。
- ScenePhotoView 的照片本身不应和每个 pin 重复朗读无意义描述；照片一个摘要，每个 pin 单独可聚焦。
- pin 的 VoiceOver hint 使用中文，包含位置说明和操作；支持“编辑”“删除” custom actions。
- 超大辅助字号下：场景网格降为单列；Items 顶部照片保持最小 180 pt，物品行标签允许换行；浮动 pin 标签转为照片下信息条。
- 使用系统高对比度语义颜色；所有选中状态同时至少具备形状、描边、图标或文字变化。
- 表单字段必须有持久 label；placeholder 不作为唯一标签。

## App Icon 方向

- 1024×1024，无文字、无预绘外圆角。
- 暖橙底 `WhereOrange`；深墨绿色用两到三条粗几何线形成“柜体/房间角落”；暖红定位 pin 落在一个抽屉或层板交点。
- 元素控制为三层：背景、场景轮廓、pin（含浅色小中心）。避免小物件细节、地图折线和字母 W。
- 轮廓占画布约 58–64%，pin 占 25–30%；在 29 pt 缩略尺寸仍需清楚区分。
- Icon Composer 验证 Default、Dark、Clear、Tinted/Mono；Tinted 下 pin 依靠实心/负形区分，不依赖红绿色差。

## 代码改动清单与优先级

### Must

- 新建 `Where/DesignSystem/WhereTheme.swift`：颜色、间距、圆角、通用照片占位与错误 banner token；颜色值放 Asset Catalog。
- `Where/App/RootTabView.swift`：接入真实 ItemsView，设置品牌 tint，保留系统 tab accessory 结构。
- 新建 `Where/Features/Items/ItemsView.swift` 与对应 model：实现顶部位置照片、未选状态、搜索、选中行、无独立详情页。
- 新建/完善 Items 行、标签、场景位置摘要子组件；接入 `ItemCardView`。
- `Where/Features/Scenes/ScenesView.swift`：响应式照片比例、数量 badge、空/加载/错误状态和 Dynamic Type 单列。
- `Where/Features/Scenes/ScenePhotoView.swift`：显式 pin 色、非选中权重、动态标签布局、中文 accessibility。
- `Where/Features/Scenes/SceneDetailView.swift`：照片下选中信息条；移除不可用动作或完成其实现。
- `Where/Features/Capture/SceneDraftView.swift`：持久字段 label、底部主按钮、照片更换 affordance、错误就地显示。
- `Where/Features/Capture/MarkerEditorView.swift`：新增/拖动/选择状态、空场景完成决策、触觉与 Reduce Motion。
- `Where/Features/Capture/ItemDraftSheet.swift`：字段排序、large-first detent、就地验证、保存 busy state。
- `Where/Features/Capture/SubjectPickerView.swift`：中文化、动作层级、候选选中视觉与失败回退。
- `Where/Features/Items/ItemCardView.swift`、`NoteEditorView.swift`：中文化、token、翻转/Reduce Motion、溢出文案、记录时间。
- 为上述主要状态添加 `#Preview`：light/dark、空/加载/错误/内容、普通与 accessibility 字号。

### Should

- 抽取 `SceneCard`, `ItemRow`, `LocationPhotoHeader`, `InlineStatusBanner`, `PhotoPlaceholder` 为聚焦子 View，避免主页面增长。
- 图片加载时稳定 frame 与轻量 skeleton；错误/清理 warning 改 inline banner。
- 加入 UIImpactFeedbackGenerator 或 SensoryFeedback 封装，确保业务测试不依赖 UIKit 单例。
- 为标签 chip 提供去重后的可视化输入；若工期不足，保留明确逗号文本。
- Items 切换位置照片 crossfade，Scene pin drop 动画。

### Could

- 首次翻卡提示胶囊与一次性偏好记录。
- 场景卡到详情照片的 matched transition。
- 在 iPad 宽屏改为 Items 左侧列表、右侧位置照片的 split layout；iPhone MVP 不需要。

## 验收检查

- 两个 Tab 位于底栏左侧，独立加号位于右侧且不自绘系统底栏。
- Items 点击行只更新同页顶部位置照片，不 push 详情。
- 所有关键界面在 Light/Dark、默认字号、AX5、Reduce Motion、Differentiate Without Color 下可用。
- 所有异步状态有加载、失败和重试路径；图片缺失不阻断文字内容。
- Liquid Glass 只用于系统栏、关键动作与 HUD；内容卡片保持温暖实体表面。
- App Icon 在 29 pt、Tinted/Mono 下仍能识别“场景 + 定位点”。
