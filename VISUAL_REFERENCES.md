# Visual reference set

The baseline is the Windows 11 22H2 Task Manager shown in the supplied light-theme Processes/context-menu screenshot. The centered search field follows the later Windows 11 search update, retaining the requested search functionality. These references informed the layout; this document is not a pixel-parity certification.

## Screens

[Windows Central's September 2022 tour](https://www.windowscentral.com/whats-new-task-manager-windows-11-version-22h2) includes all eight sections and their command bars. The following published images were inspected directly:

| View | Reference |
|---|---|
| Processes | User-supplied reference; [published Processes screenshot](https://cdn.mos.cms.futurecdn.net/ucZcEqBLLbwmWd2Tt8sLcT.jpg) |
| Performance | [CPU, resource list, and command menu](https://cdn.mos.cms.futurecdn.net/t7BfxETqA4dDS999ER8Y5J.jpg) |
| App history | [History table](https://cdn.mos.cms.futurecdn.net/whhNp4AGTjhZhcq5WShRUY.jpg) |
| Startup apps | [Startup table and actions](https://cdn.mos.cms.futurecdn.net/YQSdPhyqi8rFUysewjHpeS.jpg) |
| Users | [User/process groups](https://cdn.mos.cms.futurecdn.net/v9pQ4Aku44mLitwQeE4UfL.jpg) |
| Details | [Dense process table](https://cdn.mos.cms.futurecdn.net/aaB38JhxBFnA2R7LvEGqNo.jpg) |
| Services | [Service table](https://cdn.mos.cms.futurecdn.net/G3ZRDEYP3L2XMnSg3wg8GC.jpg) |
| Settings | [Settings controls and spacing](https://cdn.mos.cms.futurecdn.net/x3nwKfaZxWG6oDSwxEMtNC.jpg) |

Published screenshots remain with their original publishers; they are linked, not relicensed as project assets.

## Interaction references

- [Microsoft: Task Manager troubleshooting and logical-processor graphs](https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/support-tools-task-manager).
- [CPU graph context menu](https://cdn.mos.cms.futurecdn.net/jabCcSqC574jMDQZrSNaFg-1659-80.jpg).
- [Search-field reference](https://www.windowslatest.com/wp-content/uploads/2022/11/Task-Manager-search-bar-in-22h2.jpg).

`WindowsIcons.swift` holds the navigation and command glyph geometry. `WindowsMenu.swift` draws the flyouts, selection backgrounds, checkmarks, and submenu arrows while using NSMenu action models. The app icon is the original blue graph/gray frame Windows resource; see THIRD_PARTY_NOTICES.md and Assets/icon-sources.json for provenance.
