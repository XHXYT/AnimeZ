import TitleBar from '../components/TitleBar'
import { VideoSourcesViewModel } from '../viewmodel/VideoSourcesViewModel'
import { CustomContentDialog } from '@kit.ArkUI'

@Component
export struct GroupManager {

  @Link viewModel: VideoSourcesViewModel
  @State groupName: string = ''
  @State isNewGroup: boolean = false
  @State editingGroupName: string = ''
  @State customGroups: string[] = []

  private  dialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '添加新分组',
      contentBuilder: () => {
        this.InputBuilder()
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
              // 本地Push一下
              this.pushGroup(this.groupName)
            } else {
              this.viewModel.editCustomGroup(this.editingGroupName, this.groupName)
            }
            this.isNewGroup = false
            this.editingGroupName = ''
            this.groupName = ''
          }
        }
      ],
    }),
  });

  aboutToAppear(): void {
    this.customGroups = this.viewModel.customGroups
  }

  build() {
    Column() {
      // 标题栏
      TitleBar({
        showBack: false,
        title: '分组管理',
        button: () => {
          this.AddButton()
        }
      })

      // 分组列表
      List({ space: 12 }) {
        ForEach(this.customGroups, (group: string) => {
          ListItem() {
            Row() {
              Text(group)
                .fontSize(16)
                .layoutWeight(1)
              Blank()
              Row() {
                Text('编辑')
                  .fontSize(14)
              }
              .width(56)
              .justifyContent(FlexAlign.End)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.groupName = group
                this.editingGroupName = group
                this.dialogController.open()
              })
            }
            .height(52)
            .width('100%')
            .borderRadius(16)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.background_color'))
            .padding({ left: 12, right: 12})
          }
          .swipeAction({ end: this.DeleteButton(group) })
        }, (key: string) => key)
      }
      .padding({ left: 16, right: 16 })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddButton() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
    }
    .width(40).height(40)
    .margin({ top: 16, right: 56 })
    .backgroundColor($r('app.color.background_color_accent'))
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
  DeleteButton(group: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(24)
        .fontColor([Color.Red])
    }
    .padding(12)
    .onClick(() => {
      this.viewModel.removeCustomGroup(group)
    })
  }

  pushGroup(groupName: string) {
    if (groupName && groupName.trim() !== '') {
      const trimmedName = groupName.trim()
      // 检查是否已存在
      const exists = this.customGroups.some(group => group === trimmedName)
      if (!exists) {
        this.customGroups = [...this.customGroups, trimmedName]
      }
    }
  }

}