package com.ikev.dirian

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** One file or folder. `modified` is epoch seconds. */
data class Entry(val name: String, val isDirectory: Boolean, val size: Long, val modified: Long)

enum class GroupBy(val label: String) {
    None("None"),
    Name("Name"),
    Size("Size"),
    DateModified("Date Modified"),
}

class EntryGroup(val title: String, val entries: List<Entry>)

private val nameAscending = compareBy<Entry>({ !it.isDirectory }, { it.name.lowercase() })

fun groupEntries(entries: List<Entry>, by: GroupBy): List<EntryGroup> = when (by) {
    GroupBy.None -> listOf(EntryGroup("", entries.sortedWith(nameAscending)))

    GroupBy.Name -> entries
        .groupBy { entry -> entry.name.firstOrNull()?.takeIf { it.isLetter() }?.uppercase() ?: "#" }
        .toSortedMap()
        .map { (letter, items) -> EntryGroup(letter, items.sortedWith(nameAscending)) }

    GroupBy.Size -> ordered(
        entries,
        listOf("Folders", "Empty (0 KB)", "Under 1 MB", "1 MB – 10 MB", "10 MB – 100 MB", "Over 100 MB"),
        ::sizeBucket,
    )

    GroupBy.DateModified -> ordered(
        entries,
        listOf("Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Older"),
        ::dateBucket,
    )
}

private fun ordered(entries: List<Entry>, order: List<String>, bucket: (Entry) -> String): List<EntryGroup> {
    val buckets = entries.groupBy(bucket)
    return order.mapNotNull { title -> buckets[title]?.let { EntryGroup(title, it.sortedWith(nameAscending)) } }
}

private fun sizeBucket(entry: Entry): String {
    if (entry.isDirectory) return "Folders"
    val mb = 1024L * 1024
    return when {
        entry.size == 0L -> "Empty (0 KB)"
        entry.size < mb -> "Under 1 MB"
        entry.size < 10 * mb -> "1 MB – 10 MB"
        entry.size < 100 * mb -> "10 MB – 100 MB"
        else -> "Over 100 MB"
    }
}

/** Rolling day windows, like Dirian on the Mac, rather than calendar weeks/months. */
private fun dateBucket(entry: Entry): String {
    val zone = ZoneId.systemDefault()
    val day = Instant.ofEpochSecond(entry.modified).atZone(zone).toLocalDate()
    val age = LocalDate.now(zone).toEpochDay() - day.toEpochDay()
    return when {
        age <= 0 -> "Today"
        age == 1L -> "Yesterday"
        age < 7 -> "Previous 7 Days"
        age < 30 -> "Previous 30 Days"
        else -> "Older"
    }
}
