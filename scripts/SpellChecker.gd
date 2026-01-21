extends Node
class_name SpellChecker

## Simple spell checker using a dictionary file and word frequency
## Provides suggestions for misspelled words

signal dictionary_loaded

var dictionary: Dictionary = {}  # word -> true
var word_frequency: Dictionary = {}  # word -> frequency (for better suggestions)
var dictionary_by_first_letter: Dictionary = {}  # first_letter -> Array[String] (for fast lookup)
var is_loaded: bool = false

const DICTIONARY_PATH = "res://resources/dictionary.txt"

# Common contractions that may not be in the dictionary file
const ADDITIONAL_WORDS = [
	"I'm", "you're", "he's", "she's", "it's", "we're", "they're", "I've", "you've",
	"we've", "they've", "I'd", "you'd", "he'd", "she'd", "we'd", "they'd", "I'll",
	"you'll", "he'll", "she'll", "we'll", "they'll", "isn't", "aren't", "wasn't",
	"weren't", "hasn't", "haven't", "hadn't", "doesn't", "don't", "didn't", "won't",
	"wouldn't", "shan't", "shouldn't", "can't", "cannot", "couldn't", "mustn't",
	"let's", "that's", "who's", "what's", "where's", "when's", "why's", "how's",
	"okay", "ok", "yeah", "yep", "nope", "um", "uh", "hm", "hmm",
]

func _ready() -> void:
	load_dictionary()

## Load the dictionary from the file
func load_dictionary() -> void:
	# Common words list (highest frequency)
	var common_words = [
		"the", "be", "to", "of", "and", "a", "in", "that", "have", "I", "it", "for", "not", "on", "with",
		"he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her",
		"she", "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up",
		"out", "if", "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time",
		"no", "just", "him", "know", "take", "people", "into", "year", "your", "good", "some", "could",
		"them", "see", "other", "than", "then", "now", "look", "only", "come", "its", "over", "think",
		"also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
		"new", "want", "because", "any", "these", "give", "day", "most", "us", "is", "was", "are",
		"been", "has", "had", "were", "said", "did", "may", "very", "more", "where", "much", "here",
		"thing", "well", "only", "those", "tell", "much", "own", "made", "many", "must", "before",
	]

	# Assign very high frequency to common words
	for common_word in common_words:
		word_frequency[common_word] = 500

	# Load from dictionary file
	if FileAccess.file_exists(DICTIONARY_PATH):
		var file = FileAccess.open(DICTIONARY_PATH, FileAccess.READ)
		if file:
			var line_number = 0
			while not file.eof_reached():
				var line = file.get_line().strip_edges()
				if not line.is_empty():
					# Add both original case and lowercase
					dictionary[line] = true
					dictionary[line.to_lower()] = true
					# Set frequency: common words override, others get low frequency
					if not word_frequency.has(line.to_lower()):
						# Shorter words get slightly higher frequency
						var freq = max(10, 150 - line.length() * 3)
						word_frequency[line.to_lower()] = freq

					# Index by first letter for fast lookup
					var first_letter = line.to_lower()[0] if line.length() > 0 else ""
					if first_letter:
						if not dictionary_by_first_letter.has(first_letter):
							dictionary_by_first_letter[first_letter] = []
						dictionary_by_first_letter[first_letter].append(line.to_lower())
				line_number += 1
			file.close()
			print("SpellChecker: Loaded %d words from dictionary" % dictionary.size())
		else:
			push_error("SpellChecker: Failed to open dictionary file")
	else:
		push_warning("SpellChecker: Dictionary file not found at %s" % DICTIONARY_PATH)

	# Add contractions and informal words
	for word in ADDITIONAL_WORDS:
		dictionary[word] = true
		dictionary[word.to_lower()] = true
		word_frequency[word.to_lower()] = 150

	is_loaded = true
	dictionary_loaded.emit()

## Add a word to the dictionary (for user's custom words)
func add_word(word: String) -> void:
	if word.strip_edges().is_empty():
		return

	var clean_word = word.strip_edges().to_lower()
	dictionary[clean_word] = true
	dictionary[word.strip_edges()] = true  # Also add original case
	word_frequency[clean_word] = 50  # Medium frequency for user words

## Check if a word is spelled correctly
func is_word_correct(word: String) -> bool:
	if word.strip_edges().is_empty():
		return true

	# Check exact match
	if dictionary.has(word):
		return true

	# Check lowercase match
	if dictionary.has(word.to_lower()):
		return true

	# Check if it's a number
	if word.is_valid_float() or word.is_valid_int():
		return true

	return false

## Get spelling suggestions for a misspelled word
func get_suggestions(word: String, max_suggestions: int = 5) -> Array[String]:
	var suggestions: Array[String] = []

	if word.strip_edges().is_empty():
		return suggestions

	var word_lower = word.to_lower()
	var word_len = word_lower.length()

	# OPTIMIZATION: Only check words that start with the same first letter
	var first_letter = word_lower[0] if word_len > 0 else ""
	var words_to_check = dictionary_by_first_letter.get(first_letter, [])

	# If we have too few candidates, also check similar letters (for typos)
	if words_to_check.size() < 100:
		# Merge with dictionary keys as fallback
		words_to_check = dictionary.keys()

	# Generate candidates using edit distance
	var candidates: Dictionary = {}  # All candidates (must have prefix match)
	var candidates_checked = 0
	const MAX_CANDIDATES_TO_CHECK = 2000  # Limit search for performance

	for dict_word in words_to_check:
		candidates_checked += 1
		if candidates_checked > MAX_CANDIDATES_TO_CHECK:
			break  # Stop if we've checked enough words
		var dict_lower = dict_word.to_lower()
		var dict_len = dict_lower.length()

		# Skip words that are too different in length
		var len_diff = abs(word_len - dict_len)
		if len_diff > 3:
			continue

		var distance = levenshtein_distance(word_lower, dict_lower)

		# Only consider words within edit distance of 2
		if distance <= 2:
			# Calculate common prefix
			var prefix_match = get_common_prefix_length(word_lower, dict_lower)

			# STRICT: Require meaningful prefix match
			# For short words (2-3 chars), require at least 2 characters OR full match
			# For longer words, require at least 50% prefix match
			var min_prefix_required = 0
			if word_len <= 3:
				min_prefix_required = min(2, word_len)  # At least 2 chars or full word
			else:
				min_prefix_required = max(2, word_len / 2)  # At least half the word

			if prefix_match < min_prefix_required:
				# Skip words without sufficient prefix match
				continue

			# SIMPLIFIED SCORING: Prioritize word frequency above all else
			# This makes suggestions work like auto-completion

			var score = 0.0

			# Primary factor: Word frequency (most important!)
			if word_frequency.has(dict_lower):
				# Higher frequency = lower score (better ranking)
				score = 1000.0 - word_frequency[dict_lower]
			else:
				score = 1000.0

			# Secondary: Exact prefix match gets huge bonus
			# "thi" should prefer "this/think/thing" over "Thai/thief"
			if prefix_match == word_len:
				# Perfect prefix match - the word completes what they typed
				score -= 500.0
			else:
				# Partial prefix match
				score += (word_len - prefix_match) * 50.0

			# Tertiary: Small penalty for edit distance
			score += distance * 5.0

			# All candidates must have prefix match now
			candidates[dict_word] = score

			# OPTIMIZATION: Early exit if we have enough excellent candidates
			if candidates.size() >= 20:
				# Check if we have 5+ candidates with very good scores
				var good_candidates = 0
				for candidate_score in candidates.values():
					if candidate_score < 100:  # Very good score
						good_candidates += 1
				if good_candidates >= max_suggestions:
					break  # We have enough good suggestions, stop searching

	# Sort candidates by score (lower is better)
	var sorted_candidates = candidates.keys()
	sorted_candidates.sort_custom(func(a, b): return candidates[a] < candidates[b])

	# Debug: print suggestions for very short words
	if word_len <= 3 and sorted_candidates.size() > 0:
		print("Suggestions for '%s':" % word)
		for i in range(min(10, sorted_candidates.size())):
			var word_candidate = sorted_candidates[i]
			print("  %d. %s (score: %.2f)" % [i+1, word_candidate, candidates[word_candidate]])

	# Return top suggestions
	for i in range(min(max_suggestions, sorted_candidates.size())):
		suggestions.append(sorted_candidates[i])

	return suggestions

## Get the length of the common prefix between two strings
func get_common_prefix_length(s1: String, s2: String) -> int:
	var min_len = min(s1.length(), s2.length())
	for i in range(min_len):
		if s1[i] != s2[i]:
			return i
	return min_len

## Calculate Levenshtein distance between two strings
func levenshtein_distance(s1: String, s2: String) -> int:
	var len1 = s1.length()
	var len2 = s2.length()

	# Create a matrix to store distances
	var matrix = []
	for i in range(len1 + 1):
		matrix.append([])
		for j in range(len2 + 1):
			matrix[i].append(0)

	# Initialize first row and column
	for i in range(len1 + 1):
		matrix[i][0] = i
	for j in range(len2 + 1):
		matrix[0][j] = j

	# Calculate distances
	for i in range(1, len1 + 1):
		for j in range(1, len2 + 1):
			var cost = 0 if s1[i - 1] == s2[j - 1] else 1
			matrix[i][j] = min(
				matrix[i - 1][j] + 1,      # Deletion
				min(
					matrix[i][j - 1] + 1,  # Insertion
					matrix[i - 1][j - 1] + cost  # Substitution
				)
			)

	return matrix[len1][len2]

## Check an entire text and return misspelled word positions
func check_text(text: String) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []

	# Split text into words while tracking positions
	var regex = RegEx.new()
	regex.compile("[a-zA-Z']+")  # Match words including contractions

	var matches = regex.search_all(text)
	for match in matches:
		var word = match.get_string()
		if not is_word_correct(word):
			errors.append({
				"word": word,
				"start": match.get_start(),
				"end": match.get_end(),
				"suggestions": get_suggestions(word)
			})

	return errors
