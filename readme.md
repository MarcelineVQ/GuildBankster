# Guild Bankster

An advanced addon for Turtle WoW that provides template-based guild bank management and automated restocking capabilities.

## Overview

Guild Bankster eases guild bank management by introducing a template system that allows pre-defining what items should be stored in each slot across all guild bank tabs. The addon then automates the tedious process of restocking these slots from your inventory and personal bank.

## Key Features

### Template System
- **Visual Template Editor**: Create templates for each guild bank tab by dragging items directly onto template slots
- **Per-Guild Settings**: Each guild maintains its own separate template configurations

### Automated Restocking
- **One-Click Restocking**: Automatically deposit items from inventory and personal bank to match template quantities
- **Active Template Control**: Only templates marked as "active" participate in restocking operations
- **Smart Source Detection**: Pulls items from both inventory and personal bank (when open)

### UI Integration
- **Native Guild Bank Integration**: Adds new functionality without replacing existing UI
- **Template Tab**: Dedicated bottom tab for template management alongside existing guild bank tabs

## Usage Guide

### Creating Templates

#### Accessing Template Mode
1. Open the guild bank interface
2. Click the **"Templates"** tab at the bottom of the guild bank frame
3. Select which guild bank tab you want to create a template for by clicking the tab buttons

#### Setting Up Items
1. **Add Items**: Drag items from your inventory directly onto template slots
   - The item icon will appear in the template slot
   - Template slots correspond directly to guild bank slots
2. **Clear Slots**: Right-click on template slots to remove items
3. **Clear Cursor**: Right-click while holding an item to clear your cursor

#### Template Management
- **Activate Templates**: Right-click on template tabs to toggle between active (green) and inactive (red)
  - Only active templates participate in restocking
  - Newly created templates start as inactive by default
- **Switch Between Templates**: Left-click on template tabs to view and edit different templates

### Restocking Process

#### Preparation
1. **Gather Items**: Ensure you have the items you want to deposit in your inventory
2. **Bank Access** (Optional): Open your personal bank for additional item sources
   - Use mobile banking items, or
   - Stand at maximum range from bank NPCs (see NPC list below)
3. **Guild Bank Access**: Open the guild bank interface

#### Automated Restocking
1. Click the **"Restock"** button (located at bottom-right of guild bank frame)
2. The addon will automatically:
   - Process only templates marked as "active"
   - Switch through each guild bank tab in sequence
   - Deposit items from your inventory/bank to match template quantities

#### Restocking Behavior
- **Quantity Matching**: Deposits items to reach the quantities shown in templates
- **Source Priority**: Checks inventory first, then personal bank (if open)
- **Tab Switching**: Automatically switches tabs so you can observe progress
- **Completion Messages**: Chat notifications confirm when restocking is complete

### Bank NPC Integration
For characters without mobile banking, you can restock from your personal bank by standing at maximum interaction range from these NPCs:
-  **Horde Bank NPCs**
- - **Orgrimmar**: Koma
- - **Undercity**: Randolph Montague  
- - **Thunder Bluff**: Chesmu

- **Alliance Bank NPCs**
- - **Darnassus**: Any bank teller

## Technical Information

### Compatibility
- **Server**: Designed specifically for Turtle WoW
- **Dependencies**: Integrates with Turtle WoW's custom guild bank system

___
* This addon is made by and for `Weird Vibes` of Turtle WoW.