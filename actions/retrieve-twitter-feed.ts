"use server";

export async function retrieveTwitterFeed() {
  try {
    const response = await fetch(
      `https://api.socialdata.tools/twitter/user/1610189982395670528/tweets`,
      {
        headers: {
          Authorization: `Bearer ${process.env.BEARER_TOKEN}`,
        },
      },
    );

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const contentType = response.headers.get("content-type");
    if (!contentType || !contentType.includes("application/json")) {
      throw new Error("Oops! The API didn't return JSON");
    }

    const res = await response.json();
    return res.tweets;
  } catch (error) {
    console.error("Error fetching Twitter feed:", error);
    return [{ full_text: "" }]; // Return an empty array or handle the error as needed
  }
}
