require "wax"
require "TableViewController"

window = UI.Application:sharedApplication():keyWindow()

tableViewController = TableViewController:init()
window:addSubview(tableViewController:view())
