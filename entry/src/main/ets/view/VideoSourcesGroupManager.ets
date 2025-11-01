import TitleBar from '../components/TitleBar'
import { GroupConfig, VideoSourcesViewModel } from '../viewmodel/VideoSourcesViewModel'
import { CustomContentDialog } from '@kit.ArkUI'

@Component
export struct GroupManager {

  @ObjectLink viewModel: VideoSourcesViewModel
  @State groupName: string = ''
  @State isNewGroup: boolean = false
  @State editingGroup: GroupConfig | null = null

  private  dialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '添加新分组',
      contentBuilder: () => {
        this.AddButton()
      },
      buttons: [
        {
          value: '取消',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.isNewGroup = false
            this.groupName = ''
          }
        },
        {
          value: '确定',
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            if (this.isNewGroup) {
              this.viewModel.addCustomGroup(this.groupName)
            } else {
              this.viewModel.editCustomGroup(this.editingGroup!.value, this.groupName)
            }
            this.isNewGroup = false
            this.editingGroup = null
            this.groupName = ''
          }
        }
      ],
    }),
  });

  build() {
    Column() {
      // 标题栏
      TitleBar({
        title: '分组管理',
        button: () => {
          this.AddButton()
        }
      })

      // 分组列表
      List() {
        ForEach(this.viewModel.customGroups, (group: GroupConfig) => {
          ListItem() {
            Row() {
              Text(group.name)
                .fontSize(16)
                .layoutWeight(1)
              Blank()
              Button('编辑')
                .fontSize(14)
                .fontColor(Color.Red)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.groupName = group.name
                  this.editingGroup = group
                  this.dialogController.open()
                })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: 12
            })
          }
          .swipeAction({ end: this.DeleteButton(group) })
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.Red])
    }
    .width(80)
    .height('100%')
    .margin({ right: 86})
    .backgroundColor(Color.Red)
    .onClick(() => {
      this.isNewGroup = true
      this.groupName = ''
      this.dialogController.open()
    })
  }

  @Builder
  InputBuilder() {
    TextInput({text: this.groupName, placeholder: '请输入新分组名称' })
      .width('100%')
      .onChange((value: string) => {
        this.groupName = value
      })
  }

  @Builder
  DeleteButton(group: GroupConfig) {
    Button() {
      Image($r('app.media.ic_delete'))
        .width(20)
        .height(20)
        .fillColor(Color.White)
    }
    .width(80)
    .height('100%')
    .backgroundColor(Color.Red)
    .onClick(() => {
      this.viewModel.removeCustomGroup(group)
    })
  }

}