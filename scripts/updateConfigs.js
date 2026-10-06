// Insert configs.json documents whose key/configType is missing from the configs
// collection. Documents that exist only in the DB are printed and left in place.
//
//   update-db.sh scripts/updateConfigs.js
//   update-db.sh --eval "var configsFile='dump/configs.json'" scripts/updateConfigs.js

function readText(path) {
	if (typeof cat === "function") return cat(path);
	return require("fs").readFileSync(path, "utf8");
}

function tryRead(path) {
	try {
		var text = readText(path);
		if (text) return text;
	} catch (e) {}
	return null;
}

function idOf(doc) {
	if (doc.key != null) return "key\0" + doc.key;
	if (doc.configType != null) return "configType\0" + doc.configType;
	return null;
}

function label(doc) {
	if (doc.key != null) return "key=" + doc.key;
	if (doc.configType != null) return "configType=" + doc.configType;
	return "(no key or configType)";
}

var paths = [];
if (typeof configsFile !== "undefined" && configsFile) paths.push(configsFile);
paths.push("dump/configs.json");
paths.push("/home/ec2-user/dump/configs.json");

var text = null;
var used = null;
var i;
for (i = 0; i < paths.length; i++) {
	text = tryRead(paths[i]);
	if (text) {
		used = paths[i];
		break;
	}
}
if (!text) {
	print("Could not read configs.json. Tried: " + paths.join(", "));
	quit(1);
}

var fileDocs = JSON.parse(text);
if (Object.prototype.toString.call(fileDocs) !== "[object Array]") {
	print("configs.json must be a JSON array: " + used);
	quit(1);
}

var dbDocs = db.configs.find().toArray();
var inDb = {};
var inFile = {};
for (i = 0; i < dbDocs.length; i++) {
	var dbId = idOf(dbDocs[i]);
	if (dbId) inDb[dbId] = true;
}

var toInsert = [];
for (i = 0; i < fileDocs.length; i++) {
	var doc = fileDocs[i];
	var fileId = idOf(doc);
	if (!fileId) {
		print("Skipping configs.json entry with no key or configType at index " + i);
		continue;
	}
	inFile[fileId] = true;
	if (inDb[fileId]) continue;
	delete doc._id;
	toInsert.push(doc);
}

if (toInsert.length) db.configs.insertMany(toInsert);

print("Inserted " + toInsert.length + " entries from " + used + ":");
for (i = 0; i < toInsert.length; i++) print("  " + label(toInsert[i]));

print("");
print("DB entries not in configs.json:");
var extra = 0;
for (i = 0; i < dbDocs.length; i++) {
	var extraId = idOf(dbDocs[i]);
	if (extraId && inFile[extraId]) continue;
	extra++;
	print(label(dbDocs[i]));
	printjson(dbDocs[i]);
}
if (!extra) print("(none)");
