import axios from "axios";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Readable } from "stream";

// Remember to add policy: S3ReadOnly

const s3Client = new S3Client({ region: "us-west-2" });

// Environment variables
const base_id = process.env.FAN_TEST_DATABASE;
const table_id = process.env.TEST_DATA_TABLE;
const AIRTABLE_PAT = process.env.PERSONAL_ACCESS_TOKEN;

// root API
const AIRTABLE_API_URL = `https://api.airtable.com/v0/${base_id}/${table_id}`;

// get field_id from env
const ArtistName = process.env.NAME_FIELD;
const Location = process.env.LOCATION_FIELD;
const Contact = process.env.CONTACT_FIELD;
const Theme = process.env.THEME_FIELD;
const Medium = process.env.MEDIUM_FIELD;
const ArtistEmail = process.env.ARTIST_EMAIL_FIELD;
const Error = process.env.ERROR_FIELD;

export const handler = async (event) => {
    try {
        const bucket = event.Records[0].s3.bucket.name;
        const key = decodeURIComponent(
            event.Records[0].s3.object.key.replace(/\+/g, " ")
        );

        // get file from S3
        const { Body } = await s3Client.send(
            new GetObjectCommand({ Bucket: bucket, Key: key })
        );
        const fileContent = await streamToString(Body);

        // Parse JSON data with error handling
        let store_data;
        try {
            store_data = JSON.parse(fileContent);
        } catch (parseError) {
            console.error("JSON Parse Error:", parseError.message);
            throw new Error("Invalid JSON format in the S3 file.");
        }

        if (store_data.errorData) {
            const error_data = store_data.errorData;
            const row_id = store_data.rowId;

            try {
                const airtableResponse = await axios.patch(
                    `${AIRTABLE_API_URL}/${row_id}`,
                    {
                        fields: {
                            Error: error_data,
                        },
                    },
                    {
                        headers: {
                            Authorization: `Bearer ${AIRTABLE_PAT}`,
                            "Content-Type": "application/json",
                        },
                    }
                );
                console.log("Error stored:", airtableResponse.data);
                return {
                    statusCode: 200,
                    body: JSON.stringify({ message: "Success" }),
                };
            } catch (airtableError) {
                console.error("Airtable Error:", airtableError);
                return {
                    statusCode: 500,
                    body: JSON.stringify({
                        message: "Error storing data in Airtable",
                        details: airtableError.message,
                    }),
                };
            }
        }

        // extract data from store_data
        const artistData = store_data.data;
        const row_id = store_data.rowId;
        const artist_email = store_data.artistEmail;

        // Safely flatten the contact field
        // also handle both string and object data type
        let contactField = [];
        let contactEmail = null;
        const contact = artistData.Contact;
        const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (typeof contact === "string") {
            if (regex.test(contact)) {
                contactEmail = contact;
                contactField = ["Not provided"];
            } else {
                contactField = [contact];
            }
        } else {
            for (const key in contact) {
                if (contact[key].includes("Not provided") || key === "Email") {
                    continue;
                }
                let all = String(key);
                all += ": " + contact[key];
                contactField.push(all);
            }
            if (contactField.length === 0) {
                contactField = ["Not provided"];
            }
        }

        // console.log("raw contact:", contact);
        // console.log("Contact field:", contactField);

        let a_email = contactEmail || contact?.Email || "Not Provided";
        if (artist_email && artist_email !== "NONE") {
            a_email = artist_email;
        }

        const airtablePayLoad = {
            fields: {
                ArtistName: artistData.Name || "",
                Location: artistData.Location || "",
                ArtistEmail: a_email,
                Contact: contactField,
                Theme: artistData.Theme || [],
                Medium: artistData.Medium || [], //,
                //Status: "New Entry" // always UNCHECKED status for manual checking data entry
            },
        };

        // console.log("PATCH URL:", `${AIRTABLE_API_URL}/${row_id}`);
        // PATCH data to AirTable
        const airtableResponse = await axios.patch(
            `${AIRTABLE_API_URL}/${row_id}`,
            {
                ...airtablePayLoad,
                typecast: true, //Ensures multi-select fields match existing options or create new ones automatically
            },
            {
                headers: {
                    Authorization: `Bearer ${AIRTABLE_PAT}`,
                    "Content-Type": "application/json",
                },
            }
        );
        console.log("Record updated:", airtableResponse.data);
        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Success" }),
        };
    } catch (error) {
        console.error("Error:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error storing data in Airtable" }),
        };
    }
};

// Converts an S3 stream to a string
const streamToString = (stream) =>
    new Promise((resolve, reject) => {
        const chunks = [];
        stream.on("data", (chunk) => chunks.push(chunk));
        stream.on("end", () =>
            resolve(Buffer.concat(chunks).toString("utf-8"))
        );
        stream.on("error", reject);
    });

// console.log("Final Airtable Payload:", JSON.stringify(airtablePayLoad, null, 2));

// // POST data to AirTable
// const airtableResponse = await axios.post(AIRTABLE_API_URL, {
//   ...airtablePayLoad,
//   typecast: true //Ensures multi-select fields match existing options or create new ones automatically
// }, {
//   headers: {
//     Authorization: `Bearer ${AIRTABLE_PAT}`,
//     "Content-Type": "application/json",
//   },
// });
// console.log("Record created:", airtableResponse.data);
// return { statusCode: 200, body: JSON.stringify({ message: "Success" }) };
