import TitleBar from '../components/TitleBar'
import { VideoSourcesViewModel } from '../viewmodel/VideoSourcesViewModel'
import { CustomContentDialog } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'

@ComponentV2
export struct GroupManager {

  @Require @Param viewModel: VideoSourcesViewModel
  @Local groupName: string = ''
  @Local isNewGroup: boolean = false
  @Local editingGroupName: string = ''
  @Local customGroups: string[] = []
  private dialogId: number = -1

  aboutToAppear(): void {
    this.customGroups = this.viewModel.customGroups
  }

  build() {
    Column({space: 12}) {
      // 标题栏
      TitleBar({
        showBack: false,
        title: '分组管理',
        rightInset: 56,
        buttons: [
          {
            symbol: 'plus',
            iconSize: 24,
            width: 40,
            height: 40,
            backgroundColor: $r('app.color.background_color_accent'),
            action: () => {
              this.isNewGroup = true
              this.groupName = ''
              this.openGroupDialog()
            }
          }
        ]
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
                this.isNewGroup = false
                this.openGroupDialog()
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

  private openGroupDialog(): void {
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.GroupDialogBuilder()
      },
      alignment: DialogAlignment.Center
    }).then((dialogId: number) => {
      this.dialogId = dialogId
    }).catch((error: BusinessError) => {
      console.error(`openGroupDialog failed, code: ${error.code}, message: ${error.message}`)
    })
  }

  private closeGroupDialog(): void {
    if (this.dialogId === -1) {
      return
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId)
    } catch (error) {
      console.error(`closeGroupDialog failed, message: ${(error as BusinessError).message}`)
    }
    this.dialogId = -1
  }

  @Builder
  GroupDialogBuilder() {
    CustomContentDialog({
      primaryTitle: this.isNewGroup ? '添加新分组' : '编辑分组',
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
            this.closeGroupDialog()
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
            this.closeGroupDialog()
          }
        }
      ],
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
      // 本地列表删除处理
      this.customGroups = this.customGroups.filter(value => value != group )
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
