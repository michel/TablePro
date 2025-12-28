# TablePro Create Table UI/UX - Complete User Guide

## 🎨 Overview

The Create Table interface has been completely redesigned with a modern, TablePlus-inspired UI featuring professional styling, table-based column editor, hover interactions, and a sliding detail panel.

---

## 📖 How to Use

### Opening Create Table Dialog

Press **⌘⇧N** or use the menu to open the Create Table dialog.

---

## 🔧 Features Guide

### 1. **General Section**

**Table Name Field:**
- Click the text field at the top
- Type your table name
- The field shows placeholder text "Table Name"

**Database/Schema:**
- Read-only display showing current database
- Shown as gray text below table name

---

### 2. **Advanced Options** (Collapsible)

Click the **▸ Advanced Options** header to expand/collapse.

**MySQL/MariaDB Options:**
- **Engine**: InnoDB, MyISAM, etc.
- **Charset**: utf8mb4, utf8, etc.
- **Collation**: utf8mb4_unicode_ci, etc.
- **Comment**: Table description

**PostgreSQL Options:**
- **Tablespace**: Optional tablespace name
- **Comment**: Table description

All fields are optional - leave empty for defaults.

---

### 3. **Column Editor** (Table-Style Layout)

#### **Table Headers:**
```
⋮⋮  Name       Type        Attributes   Default   Actions
```

#### **Adding Columns:**

**Option A: Add Button**
- Click **+ Add Column** button
- Creates column named `column_N` with VARCHAR(255)

**Option B: Template Menu**
- Click **⭐ Template** dropdown
- Select from 8 pre-built templates:
  - ID (INT AUTO_INCREMENT PRIMARY KEY)
  - UUID (VARCHAR(36))
  - Email (VARCHAR(255))
  - Name (VARCHAR(100))
  - Description (TEXT)
  - Timestamp (TIMESTAMP)
  - Boolean (BOOLEAN/TINYINT)
  - JSON (JSON/TEXT)

#### **Editing Columns - Three Methods:**

**Method 1: Quick Inline Edit**
- **Double-click** column name cell → Edit name directly
- **Double-click** default value cell → Edit default directly
- Press **Enter** to save or **ESC** to cancel

**Method 2: Hover Actions**
- **Hover** over any column row
- **Click blue pencil icon (📝)** → Opens detail panel
- Other buttons appear:
  - **↑** Move column up
  - **↓** Move column down
  - **🗑** Delete column (red)

**Method 3: Double-Click Row**
- **Double-click anywhere on the row** (not on a specific cell)
- Detail panel slides in from right with all options

#### **Reordering Columns:**

**Option A: Drag & Drop**
1. **Hover** over a column row
2. **⋮⋮ drag handle** appears on the left
3. **Click and drag** to new position
4. Release to drop

**Option B: Arrow Buttons**
- Hover over row
- Click **↑** to move up
- Click **↓** to move down

#### **Deleting Columns:**
- Hover over row
- Click red **🗑** button
- Column removed immediately
- If it was a primary key, it's removed from PK list

---

### 4. **Column Detail Panel** (Side Panel)

Opens when you click edit button or double-click row.

**Panel Features:**
- **280px wide**, slides from right
- **Pushes main content left** (no overlay)
- **Smooth animation** (200ms)

**Sections in Panel:**

**BASIC**
- **Name**: Column name
- **Type**: Data type dropdown (VARCHAR, INT, TEXT, etc.)
- **Length**: For VARCHAR, CHAR (auto-shows when needed)
- **Precision/Scale**: For DECIMAL, NUMERIC (auto-shows when needed)

**CONSTRAINTS**
- ☑ **NOT NULL**: Column required
- ☑ **Auto Increment**: For INT types (MySQL/PostgreSQL)
- ☑ **Unsigned**: For numeric types (MySQL only)
- ☑ **Zero Fill**: For numeric types (MySQL only)

**DEFAULT VALUE**
- Text field for custom default
- **Quick buttons**:
  - `NULL` - Set to NULL
  - `''` - Empty string
  - `0` - Zero
  - `NOW()` - Current timestamp (for DATE/TIMESTAMP)
  - `TRUE/FALSE` - For BOOLEAN types

**COMMENT**
- Optional description for documentation

**Closing Panel:**
- Click **✕** button in header
- Press **ESC** key
- Panel slides away smoothly

---

### 5. **Visual Indicators**

**Primary Key Icon:**
- **🔑 Blue key icon** appears before column name
- Automatically shows when column is in Primary Key section

**Attribute Badges:**
- **AUTO** (purple) - Auto-increment enabled
- **NULL** (gray) - Column allows NULL
- **UNSIGNED** (orange) - Unsigned numeric (MySQL)

**Row States:**
- **Normal**: Transparent background
- **Hover**: Subtle blue tint + actions appear
- **Selected**: Blue left border (3px) + stronger blue tint

---

### 6. **Primary Key Selection**

Scroll to **Primary Key** section below the column table.

**Single Column PK:**
- ☑ Check one column (e.g., `id`)
- Key icon appears in column table

**Composite PK:**
- ☑ Check multiple columns
- All checked columns form composite key
- Order matters (first checked = first in PK)

**No PK Warning:**
- ⚠️ Orange warning if no columns selected
- "No primary key selected (not recommended)"
- Still allowed to create table without PK

---

### 7. **Foreign Keys**

**Empty State:**
```
        🔗
  No Foreign Keys Yet
  
  Click + to add a relationship
  between tables
  
    [+ Add Foreign Key]
```

**Adding:**
- Click **+** button in section header OR
- Click **+ Add Foreign Key** in empty state

**Editing FK Card:**
- **Constraint name**: Optional (auto-generated if empty)
- **Referenced table**: Table to reference
- **Columns**: Comma-separated local columns
- **Referenced columns**: Comma-separated foreign columns

**Example:**
```
Name: fk_user_posts
Referenced table: users
Columns: user_id
Referenced columns: id
```

**Deleting:**
- Click red **🗑** button on FK card

---

### 8. **Indexes**

**Empty State:**
```
        📋
  No Indexes Defined
  
  Add indexes to improve query performance
  
    [+ Add Index]
```

**Adding:**
- Click **+** button in section header OR
- Click **+ Add Index** in empty state

**Index Card:**
- **Type badge**: `UNIQUE` (blue) or `INDEX` (gray)
- **☑ Unique checkbox**: Toggle unique constraint
- **Index name**: Optional
- **Columns**: Comma-separated column list

**Example:**
```
✓ Unique
Name: idx_email_unique
Columns: email
```

**Deleting:**
- Click red **🗑** button on index card

---

### 9. **Check Constraints** (PostgreSQL/SQLite only)

**Empty State:**
```
        🛡
  No Check Constraints
  
  Add validation rules
  
    [+ Add Check Constraint]
```

**Adding:**
- Click **+** button in section header OR
- Click **+ Add Check Constraint** in empty state

**Check Card:**
- **Name**: Constraint name (optional)
- **Expression**: SQL expression to validate
  - Example: `age >= 18`
  - Example: `price > 0`
  - Example: `email LIKE '%@%'`

**Deleting:**
- Click red **🗑** button on check card

---

### 10. **SQL Preview**

Click **▸ SQL Preview** to expand.

**Features:**
- **Live preview** of generated SQL
- **Copy button** (📋 icon) in header
- **Monospaced font** for readability
- **Scrollable** (max height 200px)
- **Text selectable** for copying parts

**What's Shown:**
- CREATE TABLE statement
- All columns with types and constraints
- PRIMARY KEY definition
- CREATE INDEX statements (if any)
- ALTER TABLE for foreign keys (MySQL)
- Database-specific syntax

---

### 11. **Toolbar Actions**

**Template Management:**

**📂 Load Template**
1. Click **Load** button
2. Select from saved templates
3. Click **Load** to apply OR
4. Click **🗑** to delete template
5. Cancel to close

**💾 Save Template**
1. Click **Save** button
2. Enter template name
3. Click **Save**
4. Template saved to `~/Library/Application Support/TablePro/table_templates.json`

**Import/Duplicate:**

**📤 Import DDL**
1. Click **Import** button
2. Paste CREATE TABLE SQL
3. Click **Import**
4. Structure parsed and loaded

**📋 Duplicate Table**
1. Click **Duplicate** button
2. Wait for table list to load
3. Select existing table
4. Click **Duplicate**
5. Structure copied with "_copy" suffix

---

### 12. **Creating the Table**

**Footer Buttons:**
- **Cancel** - Close dialog without creating (⎋ ESC)
- **Create Table** - Execute creation (⌘↩)

**Validation:**
- Button **disabled** when table invalid:
  - No table name
  - No columns defined
  - Invalid column configurations

**On Success:**
- Table created in database
- Tab closed automatically
- Table appears in sidebar

**On Error:**
- Error message shown in toolbar
- Red warning icon with description
- Fix issues and try again

---

## ⌨️ Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Create Table | **⌘⇧N** |
| Close panel/dialog | **ESC** |
| Create table | **⌘↩** |
| Cancel | **⎋** |

---

## 🎨 Design Highlights

### **Professional Aesthetics**
- **TablePlus-inspired** clean, modern look
- **Dense information** without clutter
- **Smooth animations** (150-200ms transitions)
- **Consistent spacing** via design system
- **Dark mode** fully supported

### **Hover Interactions**
- **Drag handles** fade in on hover
- **Action buttons** appear on demand
- **Subtle backgrounds** for visual feedback
- **100ms animations** for snappy feel

### **Visual Hierarchy**
- **Bold section headers** (15pt semibold)
- **Card-based constraints** with borders
- **Color-coded badges** for quick scanning
- **Icon indicators** for status (🔑, 🔗, 🛡)

### **Responsive Layout**
- **Full-width table** with flexible columns
- **Fixed columns** (drag handle, actions)
- **Expanding columns** (name, type, attributes, default)
- **Side panel** (280px) pushes content smoothly

---

## 🐛 Troubleshooting

### "Edit button doesn't appear"
- **Make sure to hover** over the row for 100ms
- Check if row is selectable (click should select it)

### "Detail panel doesn't open"
- **Try double-clicking** the row (not the cell text)
- Or hover and **click the blue pencil icon**

### "Can't edit column name inline"
- **Must double-click** the name cell specifically
- Single-click selects the row
- Double-click enters edit mode

### "Primary key icon not showing"
- Check if column is **checked** in Primary Key section
- Icon only shows when column is in PK list

### "Template button is grayed out"
- Button disabled when no templates saved
- **Save a template first** to enable

---

## 📊 What's Implemented

### ✅ **Complete Features**
- Table-style column editor with full-width layout
- Hover-based interactions (drag handle + actions)
- Double-click inline editing (name, default)
- Side panel detail editor (all column properties)
- Primary key selection with visual indicators
- Foreign key constraints with card UI
- Indexes with unique toggle
- Check constraints (PostgreSQL/SQLite)
- Template save/load/delete
- DDL import parser
- Duplicate table structure
- SQL preview with copy
- ESC key to close panel
- Validation and error handling
- Professional empty states
- Collapsible sections
- Smooth animations

### ⏳ **Future Enhancements** (Not Yet Implemented)
- Keyboard shortcuts (Delete, ⌘↑/↓, Tab navigation)
- Right-click context menu
- Syntax highlighting in SQL preview
- Line numbers in SQL preview
- Undo/Redo support
- Column resize handles
- Better empty state illustrations

---

## 🎓 Tips & Best Practices

1. **Use Templates** for common column patterns
2. **Name your constraints** for better debugging
3. **Add comments** to document column purposes
4. **Preview SQL** before creating to verify
5. **Save templates** for reusable table structures
6. **Use composite PKs** when needed (multiple columns)
7. **Add indexes** on frequently queried columns
8. **Set NOT NULL** on required fields
9. **Use check constraints** for data validation
10. **Test with SQL preview** to ensure correctness

---

## 📝 Example Workflow

**Creating a Users Table:**

1. Open Create Table (⌘⇧N)
2. Type table name: `users`
3. Click **⭐ Template** → Select "ID"
4. Click **⭐ Template** → Select "Email"
5. Click **⭐ Template** → Select "Name"
6. Click **⭐ Template** → Select "Timestamp" (for created_at)
7. **Primary Key**: Check `id` ✓
8. **Index**: Add index on `email` (unique)
9. Click **▸ SQL Preview** to verify
10. Click **Create Table**

**Result:**
```sql
CREATE TABLE `users` (
    `id` INT AUTO_INCREMENT,
    `email` VARCHAR(255) NOT NULL,
    `name` VARCHAR(100),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 🚀 Success!

You now have a **professional-grade table creation interface** that rivals TablePlus in functionality and exceeds it in discoverability!

**Enjoy building your database schema!** 🎉
