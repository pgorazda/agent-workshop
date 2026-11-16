extends GutTest
## The places of the bar and of the overview (phase G-6): the tabs, the page boxes with their window and arrows, the follow switch,
## the menu, the pace levels and the cards. The numbers are those of the mockup's `arenas.js`.

const BarLayout := preload("res://src/core/bar_layout.gd")


func _pages(n: int) -> Array[int]:
	var list: Array[int] = []
	for i in n:
		list.append(i)
	return list


func test_the_four_tabs_are_in_a_row_with_gaps() -> void:
	assert_eq(BarLayout.tab_x(0), 14)
	assert_eq(BarLayout.tab_x(1), 97)
	assert_eq(BarLayout.tab_x(3), 263)
	assert_eq(BarLayout.tab_rect(2), Rect2i(180, 233, 80, 9))
	assert_eq(BarLayout.page_x0(), 348, "the boxes of the pages start after the fourth tab")


func test_one_page_has_no_boxes_and_the_list_ends_after_the_tabs() -> void:
	var list: Dictionary = BarLayout.page_list(_pages(1), 0)
	assert_true((list["items"] as Array).is_empty())
	assert_eq(list["end"], BarLayout.tab_x(4) - BarLayout.TAB_GAP)


func test_three_pages_are_three_boxes() -> void:
	var list: Dictionary = BarLayout.page_list(_pages(3), 1)
	var items: Array = list["items"]
	assert_eq(items.size(), 3)
	assert_eq(items[0]["rect"], Rect2i(348, 233, 12, 9))
	assert_eq(items[1]["rect"], Rect2i(362, 233, 12, 9))
	assert_eq(items[2]["rect"], Rect2i(376, 233, 12, 9))
	assert_eq(list["end"], 388)


func test_ten_pages_show_at_most_five_boxes_around_the_page_with_an_arrow_at_each_end() -> void:
	var list: Dictionary = BarLayout.page_list(_pages(10), 6)
	var shown: Array = list["shown"]
	assert_eq(shown.size(), BarLayout.PAGE_WINDOW)
	assert_eq(shown, [4, 5, 6, 7, 8], "the window is round the page of the list")
	assert_eq(list["before"], [0, 1, 2, 3])
	assert_eq(list["after"], [9])
	var items: Array = list["items"]
	assert_eq(items.size(), 7, "two arrows and five boxes")
	assert_eq(items[0]["kind"], "arrow")
	assert_eq(items[0]["side"], -1)
	assert_eq(items[0]["page"], 3, "an arrow goes to the nearest page beyond it")
	assert_eq(items[6]["kind"], "arrow")
	assert_eq(items[6]["page"], 9)
	var right_end: int = (items[6]["rect"] as Rect2i).end.x
	assert_lt(right_end, BarLayout.FOLLOW_RIGHT - BarLayout.FOLLOW_W, "two arrows and five boxes fit beside the follow switch")


func test_the_window_stays_inside_the_pages_at_the_ends() -> void:
	var first: Dictionary = BarLayout.page_list(_pages(10), 0)
	assert_eq(first["shown"], [0, 1, 2, 3, 4])
	assert_true((first["before"] as Array).is_empty())
	var last: Dictionary = BarLayout.page_list(_pages(10), 9)
	assert_eq(last["shown"], [5, 6, 7, 8, 9])
	assert_true((last["after"] as Array).is_empty())


func test_the_follow_switch_is_at_the_right_end_and_wider_in_manual() -> void:
	assert_eq(BarLayout.follow_rect(false, 37), Rect2i(443, 233, 33, 9))
	assert_eq(BarLayout.follow_rect(true, 37), Rect2i(439, 233, 37, 9))


func test_the_menu_has_eight_lines_and_two_pace_arrows() -> void:
	assert_eq(BarLayout.MENU_LINES, 8)
	assert_eq(BarLayout.menu_line_centre(0), Vector2i(410, 144))
	assert_eq(BarLayout.menu_line_rect(0), Rect2i(351, 139, 124, 11))
	for i in BarLayout.MENU_LINES:
		assert_true(BarLayout.MENU.encloses(BarLayout.menu_line_rect(i)), "line %d is inside the menu" % i)
	assert_eq(BarLayout.pace_arrow_rect(-1).size, Vector2i(9, 9))
	assert_lt(BarLayout.pace_arrow_rect(-1).position.x, BarLayout.pace_arrow_rect(1).position.x)
	assert_true(BarLayout.MENU.encloses(BarLayout.pace_arrow_rect(1)))


func test_the_pace_goes_up_and_down_by_one_move_in_ten_seconds_and_then_has_no_limit() -> void:
	assert_almost_eq(BarLayout.next_pace(0.3, 10.0, -1), 0.2, 1e-9)
	assert_almost_eq(BarLayout.next_pace(0.3, 10.0, 1), 0.4, 1e-9)
	assert_almost_eq(BarLayout.next_pace(0.1, 10.0, -1), 0.1, 1e-9, "one move in 10 s is the lowest level")
	assert_almost_eq(BarLayout.next_pace(1.0, 10.0, 1), INF, 1e-9, "above 10 moves in 10 s there is no limit")
	assert_almost_eq(BarLayout.next_pace(INF, 10.0, -1), 1.0, 1e-9, "from no limit back to 10 moves")
	assert_eq(BarLayout.next_pace(INF, 10.0, 1), INF)


func test_five_full_cards_fill_the_row_and_a_row_of_three_leaves_room_for_five() -> void:
	var five: Array[Rect2i] = BarLayout.card_rects(5, false)
	assert_eq(five.size(), 5)
	assert_eq(five[0].position.x, 4)
	assert_eq(five[0].size, Vector2i(92, 25))
	assert_eq(five[4].end.x, 472)
	var three: Array[Rect2i] = BarLayout.card_rects(3, false)
	assert_eq(three[0].size.x, five[0].size.x, "three full cards are as wide as five: the row keeps room for five")


func test_compact_cards_share_the_row_equally() -> void:
	var six: Array[Rect2i] = BarLayout.card_rects(6, true)
	assert_eq(six.size(), 6)
	assert_eq(six[0].size.x, 77)
	var twelve: Array[Rect2i] = BarLayout.card_rects(12, true)
	assert_eq(twelve[0].size.x, 37)
	assert_lte(twelve[11].end.x, 476)
	assert_true(BarLayout.card_rects(0, false).is_empty())


func test_the_cards_of_a_hovered_arena_start_after_its_plate() -> void:
	var rects: Array[Rect2i] = BarLayout.card_rects(2, false, 18, 451)
	assert_eq(rects[0].position.x, 18)
	assert_lte(rects[1].end.x, 469)


func test_the_overview_cells_are_a_two_by_two_matrix_of_half_rooms() -> void:
	assert_eq(BarLayout.CELLS.size(), 4)
	assert_eq(BarLayout.CELLS[0], Rect2i(0, 0, 240, 116))
	assert_eq(BarLayout.CELLS[3], Rect2i(240, 116, 240, 116))
	assert_eq(BarLayout.EDGE_ARROWS[0].position.x, 0)
	assert_eq(BarLayout.EDGE_ARROWS[1].end.x, 480)
