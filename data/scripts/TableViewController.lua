waxClass("TableViewController", UI.TableViewController, {protocols = {"UITableViewDelegate", "UITableViewDataSource"}})

function init(self)
  self.super:init()
  self.states = {"Michigan", "California", "New York", "Illinois", "Minnesota", "Florida"}
  return self
end

function viewDidLoad(self)
  self:tableView():setDataSource(self)
  self:tableView():setDelegate(self)  
end

-- DataSource
-------------
function numberOfSectionsInTableView(self, tableView)
  return 1
end

function tableView_numberOfRowsInSection(self, tableView, section)
  return #self.states
end

function tableView_cellForRowAtIndexPath(self, tableView, indexPath)  
  local identifier = "BasicTableViewCell"
  local cell = tableView:dequeueReusableCellWithIdentifier(identifier)
  cell = cell or UI.TableViewCell:initWithStyle_reuseIdentifier(UITableViewCellStyleDefault, identifier)  

  cell:setText(self.states[indexPath:row() + 1]) -- Must +1 because lua arrays are 1 based

  return cell
end

-- Delegate
-----------
function tableView_didSelectRowAtIndexPath(self, tableView, indexPath)
  tableView:deselectRowAtIndexPath_animated(indexPath, true)
  -- Do something cool here!
end

